import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "inkay.thermal"

  // Settings with defaults
  readonly property int warnAt: Number(setting("warnAt", 80))
  readonly property int critAt: Number(setting("critAt", 90))
  readonly property int pollMs: Math.max(500, Number(setting("pollMs", 2000)))
  readonly property bool useFahrenheit: setting("useFahrenheit", false) === true
  readonly property bool showBar: setting("showBar", true) === true
  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property string displaySensor: String(setting("displaySensor", "max"))

  property var sensors: []
  property real maxTemp: 0
  property var history: []
  property int historyMax: 60
  property bool hasData: sensors.length > 0

  readonly property string currentDisplayC: {
    if (!hasData) return "—"
    var c = Model.displayTempCForMode(sensors, displaySensor)
    return isFinite(c) ? String(c) : String(maxTemp)
  }
  readonly property real currentDisplayTemp: {
    var v = Number(currentDisplayC)
    return isFinite(v) ? v : maxTemp
  }
  readonly property string level: Model.tempLevel(currentDisplayTemp, warnAt, critAt)
  readonly property string levelLbl: Model.levelLabel(level)
  readonly property color heatColor: Model.heatColor(currentDisplayTemp, warnAt, critAt)
  readonly property string iconGlyph: Model.iconForLevel(level)
  readonly property string displayText: {
    if (!hasData) return showIcon ? iconGlyph + " —" : "—"
    var txt = Model.displayTempForMode(sensors, displaySensor, useFahrenheit)
    if (displaySensor === "all") {
      // all mode already has temps, add icon prefix if requested
      return showIcon ? iconGlyph + " " + txt : txt
    }
    return showIcon ? iconGlyph + " " + txt : txt
  }
  // Short tooltip: only primary sensors (no ACPI) to avoid bar-wide overflow
  readonly property var primarySensors: {
    var out = []
    for (var i = 0; i < sensors.length; i++) {
      var lab = String(sensors[i].label || "")
      if (lab.indexOf("ACPI") !== 0) out.push(sensors[i])
    }
    return out
  }
  readonly property string tooltip: {
    var src = primarySensors.length > 0 ? primarySensors : sensors
    var base = Model.tooltipText(src, useFahrenheit)
    // keep short: primary + level, without duplicate unit
    if (base.length > 80) base = base.substring(0, 77) + "…"
    return base + "  ·  " + levelLbl
  }

  // For panel
  readonly property var panelObject: panelLoader.item
  readonly property bool panelOpened: panelObject ? panelObject.opened === true : false

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  function open() { if (panelObject) panelObject.open() }
  function close() { if (panelObject) panelObject.close() }
  function toggle() { if (panelObject) panelObject.toggle() }
  function refresh() {
    if (!pollProc.running) pollProc.running = true
  }

  function toggleUnit() {
    if (!root.bar || !root.bar.shell) return
    var next = !root.useFahrenheit
    var newSettings = Object.assign({}, root.settings, { useFahrenheit: next })
    root.bar.shell.updateEntryInline(root.moduleName, newSettings)
  }

  function updateFromRaw(text) {
    var parsed = Model.parseSensorsJson(text, useFahrenheit)
    // If parsed empty but raw is JSON array, try fallback raw may be from get_temps.py already parsed above
    // Model handles both
    if (parsed.length === 0) {
      // try to check if raw was empty due to python fallback needing sensors -j
      // keep last known data if empty transient
      return
    }
    // Filter out sensors we don't want to show in bar's max? Keep all but panel will show all
    // Sort already done in python
    sensors = parsed
    var m = Model.maxTemp(parsed)
    maxTemp = m

    // history ring
    var h = history.slice()
    h.push(m)
    if (h.length > historyMax) h = h.slice(h.length - historyMax)
    history = h
  }

  // Visibility: show when we have data, or during initial load (show placeholder)
  // Never hide completely — placeholder helps discover widget
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  IpcHandler {
    target: "inkay.thermal"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function toggleSensors(): void { if (panelObject) panelObject.sensorsExpanded = !panelObject.sensorsExpanded }
    function expandSensors(): void { if (panelObject) panelObject.sensorsExpanded = true }
    function collapseSensors(): void { if (panelObject) panelObject.sensorsExpanded = false }
    function state(): string {
      return JSON.stringify({
        sensors: root.sensors,
        maxTemp: root.maxTemp,
        level: root.level,
        displayText: root.displayText
      })
    }
  }

  // Polling process: python helper -> sensors -j fallback
  Process {
    id: pollProc
    command: ["bash", "-c", "python3 $HOME/.config/omarchy/plugins/inkay.thermal/get_temps.py 2>/dev/null || sensors -j 2>/dev/null || echo '[]'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateFromRaw(text)
    }
  }

  Timer {
    id: pollTimer
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Re-trigger when poll interval setting changes
  onPollMsChanged: {
    pollTimer.interval = pollMs
    pollTimer.restart()
  }

  // Bar widget button
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: root.tooltip
    horizontalMargin: 8.5
    verticalPadding: 6
    // Use Style spacing for consistency, highlight when hot
    // Color animates via WidgetButton's Behavior
    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        // Right click toggles unit
        root.toggleUnit()
      } else if (btn === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }

    // Heat bar as thin underline fill (like power batteryFill but horizontal)
    // Placed at bottom of button
    Rectangle {
      id: heatTrack
      visible: root.showBar && root.hasData
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 4
      anchors.rightMargin: 4
      anchors.bottomMargin: 2
      height: 2
      radius: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    }

    Rectangle {
      id: heatFill
      visible: root.showBar && root.hasData
      anchors.left: heatTrack.left
      anchors.verticalCenter: heatTrack.verticalCenter
      height: heatTrack.height
      radius: heatTrack.radius
      width: {
        if (!root.hasData) return 0
        var frac = Model.barFraction(root.currentDisplayTemp, 100)
        // if displaySensor == max use maxTemp, else currentDisplayTemp
        // 100°C full
        return Math.max(height, heatTrack.width * frac)
      }
      color: root.heatColor

      Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 220 } }

      // Pulse when critical
      SequentialAnimation on opacity {
        running: root.level === "crit" && root.hasData
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.5; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.5; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
      }
    }
  }
}
