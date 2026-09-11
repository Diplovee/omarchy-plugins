import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GoreState.js" as Gore

// Gore Control — bar widget.
//
// Stage 3: SSH reachability polling with failure debouncing, offline
// backoff, local-network gating (nmcli), post-resume grace period,
// and transition-only desktop notifications via org.freedesktop.Notifications.
// Health polling and the panel arrive in later stages.
BarWidget {
  id: root
  moduleName: "inkay.gore"

  // Config (shell.json entry, defaults in manifest.json).
  readonly property string sshHost: String(setting("host", "gore"))
  readonly property string displayName: String(setting("displayName", "Gore")).toUpperCase()
  readonly property int pollSec: Math.max(2, Number(setting("pollIntervalSeconds", 5)))
  readonly property int connectTimeoutSec: Math.min(30, Math.max(1, Number(setting("connectTimeoutSeconds", 2))))
  readonly property int failThreshold: Math.min(10, Math.max(1, Number(setting("offlineFailureThreshold", 3))))
  readonly property bool notifyDisconnect: setting("notifyDisconnect", true) === true
  readonly property bool notifyReconnect: setting("notifyReconnect", true) === true
  readonly property bool notifyHealth: setting("notifyHealthProblems", true) === true
  readonly property int diskWarnPct: Number(setting("diskWarningPercent", 85))

  // Connection state (plain fields; GoreState.js owns the transitions).
  property string conn: Gore.CONN.UNKNOWN
  property string health: "unknown"
  property var healthReasons: []
  property var statusData: null

  // Metric history for panel sparklines (capped rings).
  property var cpuHistory: []
  property var loadHistory: []
  readonly property int historyMax: 40

  function pushHistory() {
    if (!root.statusData) return
    var cpu = Number(root.statusData.cpuPercent)
    if (isFinite(cpu)) {
      var ch = root.cpuHistory.slice()
      ch.push(cpu)
      if (ch.length > root.historyMax) ch = ch.slice(ch.length - root.historyMax)
      root.cpuHistory = ch
    }
    if (root.statusData.load) {
      var ld = Number(root.statusData.load.oneMinute)
      if (isFinite(ld)) {
        var lh = root.loadHistory.slice()
        lh.push(ld)
        if (lh.length > root.historyMax) lh = lh.slice(lh.length - root.historyMax)
        root.loadHistory = lh
      }
    }
  }
  property int failures: 0
  property double lastSuccessMs: 0
  property double disconnectMs: 0
  property double lastChangeMs: 0

  // Resume grace bookkeeping.
  property double lastWallMs: 0
  property double graceUntilMs: 0
  readonly property int resumeGraceMs: 12000
  readonly property bool inGrace: Date.now() < root.graceUntilMs

  readonly property var display: Gore.displayFor(root.conn, root.health)

  readonly property string tooltip: {
    var name = String(setting("displayName", "Gore"))
    if (root.conn === Gore.CONN.ONLINE) {
      var up = root.statusData && isFinite(Number(root.statusData.uptimeSeconds))
        ? " · uptime " + Gore.formatUptimeSec(Number(root.statusData.uptimeSeconds)) : ""
      var extra = root.health === "degraded" ? "\nNeeds attention" : "\nSSH reachable"
      return name + "\nOnline" + up + extra
    }
    if (root.conn === Gore.CONN.LOCAL_NET) {
      return name + "\nNo local network"
    }
    if (root.conn === Gore.CONN.OFFLINE || root.conn === Gore.CONN.DEGRADED) {
      var seen = root.lastSuccessMs > 0
        ? Gore.timeAgoMs(root.lastSuccessMs, Date.now()) : "never"
      return name + "\nOffline\nLast seen " + seen
    }
    return name + "\nConnecting…"
  }

  // Poll interval with offline backoff: 1x, 2x, 3x, 6x (30s max at 5s base).
  readonly property int pollIntervalMs: {
    var base = root.pollSec * 1000
    if (root.conn !== Gore.CONN.OFFLINE) return base
    var step = Math.max(0, root.failures - root.failThreshold)
    var mult = [1, 2, 3, 6][Math.min(step, 3)]
    return Math.min(30000, base * mult)
  }

  function snapshot() {
    return {
      conn: root.conn, failures: root.failures,
      lastSuccessMs: root.lastSuccessMs, disconnectMs: root.disconnectMs,
      lastChangeMs: root.lastChangeMs, health: root.health, healthReasons: root.healthReasons
    }
  }

  function restore(snap) {
    root.conn = snap.conn
    root.failures = snap.failures
    root.lastSuccessMs = snap.lastSuccessMs
    root.disconnectMs = snap.disconnectMs
    root.lastChangeMs = snap.lastChangeMs
  }

  // Shared tail for "SSH worked" outcomes: record success, then set
  // health. Emits transition notifications (reconnect / health).
  function applyReachable(snap, now, newHealth, newReasons) {
    var wasDown = snap.conn === Gore.CONN.OFFLINE || snap.conn === Gore.CONN.DEGRADED
    var outage = wasDown && snap.disconnectMs > 0 ? now - snap.disconnectMs : 0
    var prevHealth = snap.health
    var res = Gore.onCheckResult(snap, true, now, root.failThreshold)
    restore(snap)
    root.health = newHealth
    root.healthReasons = newReasons
    if (res.changed) {
      // Reconnecting from a local-network outage is not a Gore event.
      if (!(res.next === Gore.CONN.ONLINE && res.prev === Gore.CONN.LOCAL_NET)) {
        handleTransition(res.prev, res.next, outage)
      }
    }
    if (newHealth === "degraded" && prevHealth !== "degraded"
        && root.notifyHealth && now >= root.graceUntilMs
        && (root.conn === Gore.CONN.ONLINE)) {
      root.notify("Gore needs attention", String(newReasons[0] || "Health check failed."), "normal")
    }
  }

  // Single probe per poll: `gore-status --json` over SSH.
  // Exit-code disambiguation (gore-status only ever exits 0/1/2):
  //   0           -> SSH reachable, status parsed
  //   255         -> SSH-level failure (timeout, refused, DNS)
  //   other       -> SSH reachable, remote command failed (127 = missing)
  function onProbeResult(exitCode, output) {
    var now = Date.now()
    root.lastCheckMs = now
    if (exitCode === 255) {
      // Connectivity failure (grace-aware: post-resume blips are ignored).
      if (now < root.graceUntilMs) return
      var snap = snapshot()
      var res = Gore.onCheckResult(snap, false, now, root.failThreshold)
      restore(snap)
      if (res.changed) handleTransition(res.prev, res.next, 0)
      return
    }
    if (exitCode === 0) {
      var parsed = Gore.parseStatusJson(output)
      if (parsed.ok && Gore.isValidStatus(parsed.data)) {
        root.statusData = parsed.data
        root.pushHistory()
        var s2 = snapshot()
        var evald = Gore.evaluateHealth(parsed.data, root.diskWarnPct)
        applyReachable(s2, now, evald.health, evald.reasons)
        return
      }
      root.statusData = null
      var s3 = snapshot()
      applyReachable(s3, now, "degraded", ["Status report was malformed."])
      return
    }
    root.statusData = null
    var s4 = snapshot()
    var reason = exitCode === 127
      ? "gore-status is not installed on Gore."
      : "Status command failed (exit " + exitCode + ")."
    applyReachable(s4, now, "degraded", [reason])
  }

  function notify(summary, body, urgency) {
    var level = urgency === "critical" ? "2" : "1"
    Quickshell.execDetached(["busctl", "--user", "--", "call",
      "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
      "Gore Control", "0", "", summary, body,
      "0",
      "1", "urgency", "y", level,
      "-1"])
  }

  function handleTransition(prev, next, outageMs) {
    if (Date.now() < root.graceUntilMs) return
    if (next === Gore.CONN.OFFLINE && root.notifyDisconnect) {
      var darkFor = Gore.formatDurationMs(root.failThreshold * root.pollSec * 1000)
      root.notify("Gore disconnected",
        "SSH connection to Gore has been unavailable for " + darkFor + ".",
        "critical")
    } else if (next === Gore.CONN.ONLINE && root.notifyReconnect
        && (prev === Gore.CONN.OFFLINE || prev === Gore.CONN.DEGRADED)
        && outageMs > 0) {
      root.notify("Gore is back online",
        "Connection restored after " + Gore.formatDurationMs(outageMs) + ".",
        "normal")
    }
    // DEGRADED is provisional: no notification. LOCAL_NET transitions
    // never notify (a dead laptop network is not a Gore crash).
  }

  function poll() {
    if (netProc.running || sshProc.running) return
    var now = Date.now()
    // Suspend/resume: the timer stalls while asleep, so a large wall-clock
    // gap means we just resumed. Restart cleanly with a grace period
    // instead of declaring Gore offline.
    if (Gore.resumedSince(root.lastWallMs, now, root.pollIntervalMs + 20000)) {
      root.failures = 0
      root.graceUntilMs = now + root.resumeGraceMs
    }
    root.lastWallMs = now
    var snap = snapshot()
    if (snap.conn === Gore.CONN.UNKNOWN) {
      Gore.onPollStart(snap)
      restore(snap)
    }
    netProc.running = true
  }

  function onLocalNetResult(usable) {
    var now = Date.now()
    if (!usable) {
      var snap = snapshot()
      if (Gore.onLocalNetDown(snap, now)) restore(snap)
      return
    }
    // Local network is (back) usable. Parked LOCAL_NET state restarts
    // cleanly as a fresh connection attempt, silently.
    if (root.conn === Gore.CONN.LOCAL_NET) {
      root.conn = Gore.CONN.CONNECTING
      root.lastChangeMs = now
    }
    sshProc.running = true
  }

  function refresh() {
    pollTimer.restart()
    root.poll()
  }

  // Panel lifecycle (panel content lives in Panel.qml).
  readonly property var panelObject: panelLoader.item

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  // The panel is loaded asynchronously.  A click immediately after the bar
  // starts (or while the shell is busy) can otherwise be lost because the
  // Loader has no item yet.  Queue the request until Loader.onLoaded runs.
  function openPanel() {
    panelLoader.active = true
    if (panelObject) {
      panelObject.open()
      return
    }
    Qt.callLater(function() {
      if (panelObject) panelObject.open()
    })
  }
  function closePanel() { if (panelObject) panelObject.close() }
  // Bar.summonBarWidget uses this contract for reliable panel routing,
  // including when the host is offline.
  readonly property bool opened: panelObject ? panelObject.opened === true : false
  function open() { openPanel() }
  function close() { closePanel() }
  function togglePanel() {
    if (panelObject) {
      panelObject.toggle()
      return
    }
    openPanel()
  }

  // Single press handler shared by the bar button and the `click` IPC
  // (lets us verify the press path headlessly).
  function handlePress(btn) {
    if (btn === Qt.MiddleButton) {
      root.refresh()
    } else if (btn === Qt.LeftButton) {
      // Left-click opens (and refreshes) the panel; it never closes it.
      // Dismissal is handled by outside-clicks or ESC, so a click on the
      // bar icon can't feel like it "always closes".
      root.openPanel()
      Qt.callLater(function() {
        if (root.panelObject) root.panelObject.refresh()
      })
    }
  }

  function stateJson() {
    return JSON.stringify({
      state: root.conn,
      display: root.display,
      health: root.health,
      healthReasons: root.healthReasons,
      uptimeSeconds: root.statusData ? root.statusData.uptimeSeconds : null,
      failures: root.failures,
      lastSuccessMs: root.lastSuccessMs,
      inGrace: root.inGrace,
      panelLoaded: root.panelObject !== null && root.panelObject !== undefined,
      panelOpened: root.panelObject ? root.panelObject.opened === true : false,
      host: root.sshHost
    })
  }

  property double lastCheckMs: 0

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "inkay.gore"
    function toggle(): void { root.togglePanel() }
    function click(): void {
      root.openPanel()
      Qt.callLater(function() {
        if (root.panelObject) root.panelObject.refresh()
      })
    }
    function refresh(): void { root.refresh() }
    function state(): string { return root.stateJson() }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Local-network gate: only SSH when the machine itself is connected.
  // Fail-open: any ambiguity proceeds to the SSH check.
  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "STATE", "general", "status"]
    stdout: StdioCollector {
      id: netOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var text = netOut.text
      if (exitCode !== 0 || String(text || "").trim() === "") {
        root.onLocalNetResult(true) // fail-open
      } else {
        root.onLocalNetResult(Gore.localNetUsable(text))
      }
    }
  }

  // Single probe: gore-status over SSH (connectivity + health in one
  // connection). Argument array — no shell interpolation of the hostname.
  Process {
    id: sshProc
    command: ["ssh", "-o", "BatchMode=yes",
              "-o", "ConnectTimeout=" + root.connectTimeoutSec,
              "-o", "StrictHostKeyChecking=yes",
              root.sshHost, "gore-status", "--json"]
    stdout: StdioCollector {
      id: sshOut
      waitForEnd: true
    }
    onExited: function(exitCode) { root.onProbeResult(exitCode, sshOut.text) }
  }

  Timer {
    id: pollTimer
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  onPollIntervalMsChanged: pollTimer.restart()

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.display.glyph + " " + root.displayName
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: root.tooltip
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(btn) { root.handlePress(btn) }
  }
}
