import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ShgState.js" as Shg

// SHG Control — bar widget. Owns all state (devices, projects, doctor issues);
// Panel.qml is a view over it plus action launchers.
BarWidget {
  id: root
  moduleName: "inkay.shg"

  readonly property int pollSec: Math.max(2, Number(setting("pollIntervalSeconds", 4)))
  readonly property bool notifyDisconnect: setting("notifyDisconnect", true) === true
  readonly property bool notifyConnect: setting("notifyConnect", true) === true
  readonly property var scanRoots: {
    var v = setting("scanRoots", ["~/Projects", "~/Musika", "~/shg"])
    return Array.isArray(v) ? v : ["~/Projects"]
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/inkay-shg"

  // ---- devices ----
  property var devices: []
  property bool adbOk: true
  property bool devicesLoaded: false
  readonly property var readyDevices: devices.filter(function(d) { return d.state === "device" })
  readonly property var problemDevices: devices.filter(function(d) { return d.state !== "device" })

  // ---- projects ----
  property var recents: []      // [{path, lastUsed}]
  property var scanned: []      // [path]
  property string currentProject: ""
  readonly property var projects: Shg.mergeProjects(recents, scanned)

  // ---- issues (shg doctor) ----
  property var issues: []
  property bool doctorRunning: false
  property double doctorAtMs: 0
  property string doctorError: ""

  readonly property string glyph: !adbOk ? "󰀦" : (readyDevices.length > 0 ? "󰄜" : (problemDevices.length > 0 ? "󰀦" : "󰄜"))
  readonly property string label: readyDevices.length > 0
    ? String(readyDevices.length)
    : (problemDevices.length > 0 ? "!" : "–")
  readonly property string tooltip: {
    if (!adbOk) return "SHG\nadb not available"
    var lines = ["SHG" + (currentProject ? " · " + Shg.projectName(currentProject) : "")]
    if (devices.length === 0) lines.push("No devices connected")
    devices.forEach(function(d) {
      lines.push((d.state === "device" ? "● " : "○ ") + (d.model || d.id) + " · " + d.state)
    })
    if (issues.length > 0) lines.push(issues.length + " issue(s) — open panel")
    return lines.join("\n")
  }

  function notify(summary, body, urgency) {
    Quickshell.execDetached(["busctl", "--user", "--", "call",
      "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
      "SHG", "0", "", summary, body, "0",
      "1", "urgency", "y", urgency === "critical" ? "2" : "1", "-1"])
  }

  // ---------- device polling ----------
  function refresh() {
    if (!adbProc.running) adbProc.running = true
  }

  Process {
    id: adbProc
    command: ["adb", "devices", "-l"]
    stdout: StdioCollector { id: adbOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.adbOk = false; return }
      root.adbOk = true
      var next = Shg.parseDevices(adbOut.text)
      var events = root.devicesLoaded ? Shg.diffDevices(root.devices, next) : []
      root.devices = next
      root.devicesLoaded = true
      events.forEach(function(e) {
        var name = e.device.model || e.device.id
        if (e.kind === "disconnected" && root.notifyDisconnect)
          root.notify("Android device disconnected", name, "critical")
        else if (e.kind === "connected" && root.notifyConnect)
          root.notify("Android device connected", name, "normal")
      })
    }
  }

  Timer {
    interval: root.pollSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---------- projects: recents + scan ----------
  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        root.recents = Array.isArray(s.recents) ? s.recents : []
        if (!root.currentProject && s.current) root.currentProject = String(s.current)
      } catch (e) {}
    }
  }

  Process { id: mkdirProc; command: ["mkdir", "-p", root.stateDir] }
  Component.onCompleted: { mkdirProc.running = true; scan() }

  function saveState() {
    stateFile.setText(JSON.stringify({ current: root.currentProject, recents: root.recents }, null, 2))
  }

  function selectProject(path) {
    root.currentProject = path
    root.recents = Shg.touchRecent(root.recents, path, Date.now(), 12)
    root.issues = []
    root.doctorAtMs = 0
    root.saveState()
    root.runDoctor()
  }

  function forgetProject(path) {
    root.recents = root.recents.filter(function(r) { return r.path !== path })
    if (root.currentProject === path) root.currentProject = ""
    root.saveState()
  }

  function scan() {
    if (!scanProc.running) scanProc.running = true
  }

  Process {
    id: scanProc
    // Capacitor projects (android/ next to capacitor.config.*) under the scan roots.
    command: ["sh", "-c",
      "for r in \"$@\"; do r=$(eval echo \"$r\"); [ -d \"$r\" ] && find \"$r\" -maxdepth 5 "
      + "\\( -name node_modules -o -name .git -o -name android -o -name dist \\) -prune -o "
      + "-name 'capacitor.config.*' -print; done | sed 's#/capacitor.config\\.[a-z]*$##' | sort -u",
      "sh"].concat(root.scanRoots)
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    onExited: {
      root.scanned = String(scanOut.text).split("\n").map(function(s) { return s.trim() }).filter(Boolean)
    }
  }

  // ---------- doctor ----------
  function runDoctor() {
    if (!root.currentProject || doctorProc.running) return
    root.doctorRunning = true
    root.doctorError = ""
    doctorProc.workingDirectory = root.currentProject
    doctorProc.running = true
  }

  Process {
    id: doctorProc
    // The shell env lacks JAVA_HOME; fall back to the local JDK so Java isn't a false issue.
    command: ["sh", "-c", "[ -n \"$JAVA_HOME\" ] || export JAVA_HOME=$(ls -d \"$HOME\"/.local/jdks/*/ 2>/dev/null | head -1); java -version >/dev/null 2>&1 || PATH=\"${JAVA_HOME%/}/bin:$PATH\"; exec shg doctor --json"]
    stdout: StdioCollector { id: doctorOut; waitForEnd: true }
    onExited: function(code) {
      root.doctorRunning = false
      root.doctorAtMs = Date.now()
      var parsed = Shg.parseDoctor(doctorOut.text)
      if (parsed === null) {
        root.doctorError = code === 127 ? "shg not found in PATH" : "doctor output unreadable"
        root.issues = []
      } else {
        root.issues = parsed
      }
    }
  }

  // ---------- launchers (terminal, project cwd, argv-safe) ----------
  // Runs `shg <args>` in the project dir inside an Omarchy terminal and keeps
  // the window open afterwards so output can be read.
  function runInTerminal(appId, args) {
    if (!root.currentProject) return
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.shg-" + appId,
      "sh", "-c",
      "cd \"$1\" || exit 1; shift; \"$@\"; s=$?; printf '\\n[exit %s] press enter to close' \"$s\"; read _",
      "sh", root.currentProject, "shg"].concat(args))
  }

  function runQuiet(args, notifyOk) {
    quietProc.command = ["shg"].concat(args)
    quietProc.workingDirectory = root.currentProject || root.home
    quietProc.notifyOk = notifyOk || ""
    quietProc.running = true
  }

  Process {
    id: quietProc
    property string notifyOk: ""
    stdout: StdioCollector { id: quietOut; waitForEnd: true }
    stderr: StdioCollector { id: quietErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0 && notifyOk) root.notify(notifyOk, "", "normal")
      else if (code !== 0) root.notify("shg failed (exit " + code + ")",
        String(quietErr.text || quietOut.text).trim().split("\n").slice(-2).join(" "), "critical")
      root.refresh()
    }
  }

  function disconnectDevice(id) {
    disconnectProc.command = ["adb", "disconnect", id]
    disconnectProc.running = true
  }
  Process { id: disconnectProc; onExited: root.refresh() }

  // ---------- panel plumbing (same contract as inkay.gore) ----------
  readonly property var panelObject: panelLoader.item
  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }
  function openPanel() {
    panelLoader.active = true
    if (panelObject) { panelObject.open(); return }
    Qt.callLater(function() { if (panelObject) panelObject.open() })
  }
  function closePanel() { if (panelObject) panelObject.close() }
  readonly property bool opened: panelObject ? panelObject.opened === true : false
  function open() { openPanel() }
  function close() { closePanel() }
  function togglePanel() { if (panelObject) panelObject.toggle(); else openPanel() }

  function handlePress(btn) {
    if (btn === Qt.MiddleButton) root.refresh()
    else if (btn === Qt.LeftButton) root.openPanel()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "inkay.shg"
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function select(path: string): void { root.selectProject(path) }
    function state(): string {
      return JSON.stringify({ devices: root.devices, project: root.currentProject,
        issues: root.issues.map(function(i) { return i.title + ": " + i.status + " " + i.details }), doctorError: root.doctorError, recents: root.recents.length, scanned: root.scanned.length })
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph + " " + root.label
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: root.tooltip
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(btn) { root.handlePress(btn) }
  }
}
