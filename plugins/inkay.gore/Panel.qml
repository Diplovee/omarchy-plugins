import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GoreState.js" as Gore

// Gore Control panel: two-column overview (stat cards, service chips,
// health banner) + quick actions and server controls.
// Owned by BarWidget.qml (Loader); all live data comes from hostWidget.
Panel {
  id: root
  moduleName: "inkay.gore"
  ipcTarget: "inkay.gore"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string conn: hostWidget ? hostWidget.conn : "UNKNOWN"
  readonly property string health: hostWidget ? hostWidget.health : "unknown"
  readonly property var healthReasons: hostWidget ? hostWidget.healthReasons : []
  readonly property var statusData: hostWidget ? hostWidget.statusData : null
  readonly property string sshHost: hostWidget ? hostWidget.sshHost : "gore"
  readonly property string displayName: hostWidget
    ? String(hostWidget.setting("displayName", "Gore")) : "Gore"
  readonly property string tagline: hostWidget
    ? String(hostWidget.setting("tagline", "My homelab")) : "My homelab"
  readonly property int pollSec: hostWidget ? hostWidget.pollSec : 5
  readonly property var cpuHistory: hostWidget ? hostWidget.cpuHistory : []
  readonly property var loadHistory: hostWidget ? hostWidget.loadHistory : []
  readonly property double lastCheckMs: hostWidget ? hostWidget.lastCheckMs : 0
  readonly property var display: hostWidget
    ? hostWidget.display : { glyph: "○", label: "unknown" }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool isOnline: root.conn === "ONLINE"
  readonly property bool isDegraded: root.health === "degraded"
  readonly property color stateColor: !root.isOnline
    ? root.dim : (root.isDegraded ? Color.urgent : Color.accent)
  readonly property color cardFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property color cardBorder: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  // Live "x seconds ago" ticker (panel-local; only runs while open).
  property double nowTs: Date.now()
  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowTs = Date.now()
  }
  readonly property string lastCheckedText: {
    if (!root.lastCheckMs) return "Last checked · —"
    return "Last checked · " + Gore.timeAgoMs(root.lastCheckMs, root.nowTs)
  }

  readonly property string uptimeText: {
    if (!root.statusData || !isFinite(Number(root.statusData.uptimeSeconds))) return "—"
    return Gore.formatUptimeSec(Number(root.statusData.uptimeSeconds))
  }
  readonly property string cpuText: {
    if (!root.statusData || !isFinite(Number(root.statusData.cpuPercent))) return "—"
    return Math.round(Number(root.statusData.cpuPercent)) + "%"
  }
  readonly property string loadText: {
    if (!root.statusData || !root.statusData.load) return "—"
    var l = root.statusData.load
    function short(v) {
      var n = Number(v)
      return isFinite(n) ? String(Math.round(n * 100) / 100) : String(v)
    }
    return short(l.oneMinute) + " / " + short(l.fiveMinute) + " / " + short(l.fifteenMinute)
  }
  readonly property string memText: {
    if (!root.statusData || !root.statusData.memory) return "—"
    var m = root.statusData.memory
    return Gore.formatBytes(m.usedBytes) + " / " + Gore.formatBytes(m.totalBytes)
  }
  readonly property real memFrac: {
    if (!root.statusData || !root.statusData.memory) return 0
    var m2 = root.statusData.memory
    var t = Number(m2.totalBytes)
    if (!isFinite(t) || t <= 0) return 0
    return Math.max(0, Math.min(1, Number(m2.usedBytes) / t))
  }
  readonly property string diskText: {
    if (!root.statusData || !root.statusData.disk) return "—"
    var d = root.statusData.disk
    return Gore.formatBytes(d.usedBytes) + " / " + Gore.formatBytes(d.totalBytes)
  }
  readonly property real diskFrac: {
    if (!root.statusData || !root.statusData.disk) return 0
    var p = Number(root.statusData.disk.percent)
    if (!isFinite(p)) return 0
    return Math.max(0, Math.min(1, p / 100))
  }
  readonly property string diskPctText: {
    if (!root.statusData || !root.statusData.disk
        || !isFinite(Number(root.statusData.disk.percent))) return ""
    return Math.round(Number(root.statusData.disk.percent)) + "%"
  }
  readonly property string osText: {
    if (!root.statusData || !root.statusData.osPretty) return ""
    return String(root.statusData.osPretty)
  }
  function serviceState(name) {
    if (!root.statusData || !root.statusData.services) return "—"
    return String(root.statusData.services[name] || "—")
  }
  function serviceColor(state) {
    if (state === "running") return Color.accent
    if (state === "—") return root.dim
    return Color.urgent
  }
  readonly property int failedUnits: {
    if (!root.statusData || !isFinite(Number(root.statusData.failedSystemdUnits))) return -1
    return Math.round(Number(root.statusData.failedSystemdUnits))
  }
  readonly property string updatesText: {
    if (!root.statusData || root.statusData.updatesAvailable === null
        || root.statusData.updatesAvailable === undefined
        || !isFinite(Number(root.statusData.updatesAvailable))) return "—"
    var n = Math.round(Number(root.statusData.updatesAvailable))
    return n === 0 ? "None" : String(n)
  }

  function open() {
    if (hostWidget) hostWidget.refresh()
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function refresh() { if (hostWidget) hostWidget.refresh() }

  function copySsh() {
    Quickshell.execDetached(["wl-copy", "--", "ssh " + root.sshHost])
  }

  // Launchers use Omarchy's terminal wrappers (never a hardcoded binary).
  // Static argv arrays — no shell interpolation anywhere.
  function openTerminal() {
    Quickshell.execDetached(["omarchy-launch-terminal", "ssh", root.sshHost])
    root.close()
  }
  function openHerdr() {
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.gore-herdr",
      "ssh", "-t", root.sshHost, "herdr"])
    root.close()
  }
  function openLogs() {
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.gore-logs",
      "ssh", "-t", root.sshHost,
      "journalctl", "-p", "warning..alert", "-n", "200"])
    root.close()
  }

  property string pendingPowerAction: "" // "reboot" | "poweroff" | ""

  function requestPower(action) {
    root.pendingPowerAction = action
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }
  function runPendingPower() {
    var action = root.pendingPowerAction
    root.pendingPowerAction = ""
    confirmDialog.opened = false
    if (action !== "reboot" && action !== "poweroff") return
    // Password prompt (if sudo requires one) appears in the terminal;
    // no credentials are ever handled by the plugin.
    Quickshell.execDetached(["omarchy-launch-tui",
      "--app-id=org.omarchy.gore-" + action,
      "ssh", "-t", root.sshHost, "sudo", "systemctl",
      action === "reboot" ? "reboot" : "poweroff"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(920))
    contentHeight: panel.fittedContentHeight(mainRow.implicitHeight, Style.space(780))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(dir) { root.switchPanel(dir) }
    }

    Row {
      id: mainRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(16)

      // ---------- LEFT: status overview ----------
      Column {
        id: leftCol
        width: Math.round(parent.width * 0.64)
        spacing: Style.space(12)

        // Header
        Row {
          width: parent.width
          spacing: Style.space(14)

          Text {
            text: ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(40)
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: parent.width - Style.space(40) - Style.space(14) - uptimeCol.width - Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              text: root.displayName.toUpperCase()
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Row {
              spacing: Style.space(8)

              Text {
                text: "● " + (root.isOnline
                  ? (root.isDegraded ? "Needs attention" : "Online") : root.display.label)
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "·"
                color: root.dim
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "ssh " + root.sshHost
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              PanelActionButton {
                iconText: ""
                tooltipText: "Copy SSH command"
                foreground: root.dim
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.copySsh()
              }
            }
          }

          Column {
            id: uptimeCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.uptimeText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              horizontalAlignment: Text.AlignRight
            }
            Text {
              text: "Uptime"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignRight
              width: parent.width
            }
          }
        }

        // Stat cards
        Row {
          width: parent.width
          spacing: Style.space(10)

          StatCard {
            title: "CPU"; value: root.cpuText; icon: ""
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
            sparkModel: root.cpuHistory.slice(-30); sparkMax: 100
            sparkColor: root.stateColor
          }
          StatCard {
            title: "Memory"; value: root.memText; icon: "\uefc5"
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
            barFrac: root.memFrac; barColor: Color.accent
            barLabel: root.memFrac > 0 ? Math.round(root.memFrac * 100) + "%" : ""
          }
          StatCard {
            title: "Disk"; value: root.diskText; icon: ""
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
            barFrac: root.diskFrac; barColor: root.diskFrac >= 0.85 ? Color.urgent : Color.accent
            barLabel: root.diskPctText
          }
          StatCard {
            title: "Load"; value: root.loadText; icon: ""
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
            sparkModel: root.loadHistory.slice(-30); sparkMax: -1
            sparkColor: root.dim
          }
        }

        // Service chips
        Row {
          width: parent.width
          spacing: Style.space(10)

          Chip {
            label: "SSH"; sub: root.serviceState("ssh")
            dot: root.serviceColor(root.serviceState("ssh"))
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
          }
          Chip {
            label: "Docker"; sub: root.serviceState("docker")
            dot: root.serviceColor(root.serviceState("docker"))
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
          }
          Chip {
            label: "Failed units"; sub: root.failedUnits < 0 ? "—" : String(root.failedUnits)
            dot: root.failedUnits > 0 ? Color.urgent : root.dim
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
          }
          Chip {
            label: "Updates"; sub: root.updatesText
            dot: root.updatesText !== "—" && root.updatesText !== "None" ? Color.urgent : Color.accent
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            width: (parent.width - Style.space(30)) / 4
          }
        }

        // Footer
        Item {
          width: parent.width
          implicitHeight: Math.max(checkedText.implicitHeight, refreshText.implicitHeight)

          Text {
            id: checkedText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "   " + root.lastCheckedText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            id: refreshText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "   Auto refresh · " + root.pollSec + "s"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Health banner
        Rectangle {
          width: parent.width
          implicitHeight: Math.max(Style.space(64), bannerRow.implicitHeight + Style.space(16))
          radius: Style.cornerRadius
          color: root.cardFill
          border.color: root.cardBorder
          border.width: 1

          Row {
            id: bannerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            spacing: Style.space(12)

            Text {
              text: root.isOnline && !root.isDegraded ? "" : ""
              color: root.stateColor
              font.family: root.fontFamily
              font.pixelSize: Style.space(26)
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              width: parent.width - Style.space(26) - Style.space(12) - pill.width - Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: !root.isOnline ? "Gore is unreachable"
                  : (root.isDegraded ? "Needs attention" : "All systems good")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                text: !root.isOnline ? "SSH checks are failing. Gore may be off or rebooting."
                  : (root.isDegraded ? root.healthReasons.join(" ")
                    : "Gore is online and running smoothly.")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }

            BorderSurface {
              id: pill
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: pillText.implicitWidth + Style.space(20)
              implicitHeight: pillText.implicitHeight + Style.space(10)
              radius: height / 2
              color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.14)
              borderSpec: Border.flat(root.stateColor, 1)

              Text {
                id: pillText
                anchors.centerIn: parent
                text: "● " + (!root.isOnline ? "Offline"
                  : (root.isDegraded ? "Attention" : "Healthy"))
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }
        }
      }

      // ---------- RIGHT: actions ----------
      Column {
        width: parent.width - leftCol.width - Style.space(16)
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "QUICK ACTIONS"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        ActionRow {
          width: parent.width
          title: "Open Terminal"; sub: "ssh " + root.sshHost; icon: ""
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.openTerminal()
        }
        ActionRow {
          width: parent.width
          title: "Open Herdr"; sub: "ssh -t " + root.sshHost + " herdr"; icon: ""
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.openHerdr()
        }
        ActionRow {
          width: parent.width
          title: "View Logs"; sub: "journalctl -f"; icon: ""
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.openLogs()
        }
        ActionRow {
          width: parent.width
          title: "Refresh Status"; sub: "Check now"; icon: ""
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.refresh()
        }

        PanelSectionHeader {
          text: "SERVER CONTROLS"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        ActionRow {
          width: parent.width
          title: "Restart Gore"; sub: "Reboot the server"; icon: ""
          iconColor: "#e8a65a"
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.requestPower("reboot")
        }
        ActionRow {
          width: parent.width
          title: "Shut Down Gore"; sub: "Power off the server"; icon: ""
          iconColor: Color.urgent
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.requestPower("poweroff")
        }

        Rectangle {
          width: parent.width
          implicitHeight: noteText.implicitHeight + Style.space(16)
          radius: Style.cornerRadius / 2
          color: root.cardFill
          border.color: root.cardBorder
          border.width: 1

          Text {
            id: noteText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            text: "\uf05a   These actions require sudo on Gore and will open a terminal for confirmation."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      message: root.pendingPowerAction === "poweroff"
        ? "Shut down Gore? It will stay off until powered on manually."
        : "Restart Gore? Active sessions and containers will be interrupted."
      cancelText: "Cancel"
      confirmText: root.pendingPowerAction === "poweroff" ? "Shut Down" : "Restart"
      background: Color.popups.background
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: {
        confirmDialog.opened = false
        root.pendingPowerAction = ""
      }
      onConfirmed: root.runPendingPower()
    }
  }

  // ----- local components -----

  // Stat card with either a sparkline (sparkModel) or a progress bar.
  component StatCard: BorderSurface {
    id: card
    property string title: ""
    property string value: "—"
    property string icon: ""
    property color foreground: Color.foreground
    property color dim: Color.foreground
    property color cardFill: "transparent"
    property color cardBorder: "transparent"
    property string fontFamily: Style.font.family
    property var sparkModel: null
    property real sparkMax: 100
    property color sparkColor: Color.accent
    property real barFrac: -1
    property color barColor: Color.accent
    property string barLabel: ""

    implicitHeight: Style.space(136)
    radius: Style.cornerRadius
    color: card.cardFill
    borderSpec: Border.flat(card.cardBorder, 1)
    padding: Style.space(10)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      spacing: Style.space(6)

      Text {
        text: card.icon
        color: card.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.title
      }
      Text {
        text: card.title
        color: card.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        text: card.value
        color: card.foreground
        font.family: card.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Item {
        width: parent.width
        height: Style.space(28)
        visible: card.sparkModel !== null || card.barFrac >= 0

        // Sparkline
        Row {
          anchors.fill: parent
          spacing: 2
          visible: card.sparkModel !== null

          Repeater {
            model: card.sparkModel
            delegate: Item {
              required property var modelData
              required property int index
              width: Math.max(2, (parent.width - 2 * 29) / 30)
              height: parent.height

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: {
                  var vals = card.sparkModel
                  var mx = card.sparkMax
                  if (mx <= 0) {
                    mx = 1
                    for (var i = 0; i < vals.length; i++)
                      if (Number(vals[i]) > mx) mx = Number(vals[i])
                  }
                  var v = Number(modelData)
                  if (!isFinite(v)) return 2
                  var frac = Math.max(0, Math.min(1, v / mx))
                  return Math.max(2, parent.height * (0.15 + frac * 0.85))
                }
                radius: width / 2
                color: card.sparkColor
                opacity: index === card.sparkModel.length - 1 ? 1.0 : 0.7
              }
            }
          }
        }

        // Progress bar + label
        Row {
          anchors.fill: parent
          spacing: Style.space(6)
          visible: card.barFrac >= 0

          Rectangle {
            width: parent.width - barPct.implicitWidth - Style.space(6)
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.14)

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: parent.radius
              width: Math.max(height, parent.width * Math.max(0, Math.min(1, card.barFrac)))
              color: card.barColor
            }
          }
          Text {
            id: barPct
            text: card.barLabel
            color: card.dim
            font.family: card.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  component Chip: BorderSurface {
    property string label: ""
    property string sub: "—"
    property color dot: Color.foreground
    property color foreground: Color.foreground
    property color dim: Color.foreground
    property color cardFill: "transparent"
    property color cardBorder: "transparent"
    property string fontFamily: Style.font.family

    implicitHeight: Style.space(68)
    radius: Style.cornerRadius
    color: cardFill
    borderSpec: Border.flat(cardBorder, 1)
    padding: Style.space(10)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      spacing: Style.space(3)

      Row {
        spacing: Style.space(6)

        Rectangle {
          width: 8; height: 8; radius: 4
          color: dot
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: label
          color: foreground
          font.family: fontFamily
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      Text {
        text: sub
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: parent.width
        leftPadding: Style.space(14)
      }
    }
  }

  component ActionRow: BorderSurface {
    id: row
    property string title: ""
    property string sub: ""
    property string icon: ""
    property color iconColor: row.foreground
    property color foreground: Color.foreground
    property color dim: Color.foreground
    property color cardFill: "transparent"
    property color cardBorder: "transparent"
    property string fontFamily: Style.font.family
    signal clicked()

    implicitHeight: Style.space(60)
    radius: Style.cornerRadius
    color: mouse.containsMouse
      ? Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.08) : row.cardFill
    borderSpec: Border.flat(row.cardBorder, 1)
    padding: Style.space(10)

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      spacing: Style.space(12)

      Text {
        text: row.icon
        color: row.iconColor
        font.family: row.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(26)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(26) - Style.space(20) - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          text: row.title
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: row.sub
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        text: ""
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
    }
  }
}
