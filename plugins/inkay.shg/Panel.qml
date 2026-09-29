import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "ShgState.js" as Shg

// SHG Control panel. Left: projects (recent first) + doctor issues.
// Right: devices + actions. All state lives in hostWidget (BarWidget.qml).
Panel {
  id: root
  moduleName: "inkay.shg"
  ipcTarget: "inkay.shg"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var devices: hostWidget ? hostWidget.devices : []
  readonly property var projects: hostWidget ? hostWidget.projects : []
  readonly property var issues: hostWidget ? hostWidget.issues : []
  readonly property string project: hostWidget ? hostWidget.currentProject : ""
  readonly property bool hasProject: project !== ""
  readonly property bool adbOk: hostWidget ? hostWidget.adbOk : true

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color cardFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property color cardBorder: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  property double nowTs: Date.now()
  Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.nowTs = Date.now() }

  function open() {
    if (hostWidget) { hostWidget.refresh(); hostWidget.scan() }
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function run(id, args, closeAfter) {
    if (hostWidget) hostWidget.runInTerminal(id, args)
    if (closeAfter !== false) root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(880))
    contentHeight: panel.fittedContentHeight(mainRow.implicitHeight, Style.space(760))

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

      // ================= LEFT: projects + issues =================
      Column {
        id: leftCol
        width: Math.round(parent.width * 0.5)
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "󰄜"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(34)
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(34) - Style.space(10)
            Text {
              text: "SHG"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
            Text {
              text: root.hasProject ? root.project : "No project selected"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              width: parent.width
            }
          }
        }

        PanelSectionHeader {
          text: "PROJECTS"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        Text {
          visible: root.projects.length === 0
          width: parent.width
          text: "No Capacitor projects found. Run `omarchy-shell inkay.shg select <path>` or add scan roots."
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.projects.slice(0, 5)
          delegate: ProjectRow {
            required property var modelData
            width: leftCol.width
            title: modelData.name
            sub: modelData.recent && modelData.lastUsed
              ? Shg.timeAgoMs(modelData.lastUsed, root.nowTs) + " · " + modelData.path : modelData.path
            selected: modelData.path === root.project
            recent: modelData.recent
            foreground: root.foreground; dim: root.dim
            cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.hostWidget.selectProject(modelData.path)
            onForget: root.hostWidget.forgetProject(modelData.path)
          }
        }

        Text {
          visible: root.projects.length > 5
          text: "+ " + (root.projects.length - 5) + " more (use `omarchy-shell inkay.shg select <path>`)"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSectionHeader {
          text: "ISSUES"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: hostWidget && hostWidget.doctorError ? Color.urgent : root.dim
          text: {
            if (!root.hasProject) return "Select a project to scan."
            if (!hostWidget) return ""
            if (hostWidget.doctorRunning) return "Scanning…"
            if (hostWidget.doctorError) return hostWidget.doctorError
            if (!hostWidget.doctorAtMs) return "Not scanned yet."
            return (root.issues.length === 0 ? "No issues · " : root.issues.length + " issue(s) · ")
              + "scanned " + Shg.timeAgoMs(hostWidget.doctorAtMs, root.nowTs)
          }
        }

        Repeater {
          model: root.issues
          delegate: BorderSurface {
            required property var modelData
            width: leftCol.width
            implicitHeight: issueCol.implicitHeight + Style.space(14)
            radius: Style.cornerRadius / 2
            color: root.cardFill
            borderSpec: Border.flat(root.cardBorder, 1)
            Column {
              id: issueCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(7)
              spacing: Style.space(2)
              Text {
                text: (modelData.status === "fail" ? "✕ " : "! ") + modelData.title
                color: modelData.status === "fail" ? Color.urgent : "#e8a65a"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                width: parent.width
                elide: Text.ElideRight
              }
              Text {
                visible: !!modelData.details
                text: String(modelData.details || "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      // ================= RIGHT: devices + actions =================
      Column {
        id: rightCol
        width: parent.width - leftCol.width - Style.space(16)
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "DEVICES"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        Text {
          visible: root.devices.length === 0
          width: parent.width
          text: root.adbOk ? "No devices. Pair a phone below." : "adb is not available (run shg doctor)."
          color: root.adbOk ? root.dim : Color.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.devices
          delegate: BorderSurface {
            required property var modelData
            readonly property bool ok: modelData.state === "device"
            width: rightCol.width
            implicitHeight: Style.space(56)
            radius: Style.cornerRadius
            color: root.cardFill
            borderSpec: Border.flat(root.cardBorder, 1)

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)
              Text {
                text: ok ? "●" : "○"
                color: ok ? Color.accent : Color.urgent
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                width: parent.width - Style.space(30) - Style.space(60)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  text: modelData.model || modelData.id
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  text: modelData.state + (modelData.wireless ? " · wifi" : " · usb")
                    + (modelData.state === "unauthorized" ? " — accept the prompt on the phone" : "")
                  color: ok ? root.dim : Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }
              PanelActionButton {
                visible: modelData.wireless
                iconText: "󰌸"
                tooltipText: "Disconnect"
                foreground: root.dim
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.hostWidget.disconnectDevice(modelData.id)
              }
              PanelActionButton {
                visible: ok
                iconText: "󰄄"
                tooltipText: "Screenshot"
                foreground: root.dim
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                  root.hostWidget.runQuiet(["device", "screenshot", "--device", modelData.id], "Screenshot saved")
                }
              }
            }
          }
        }

        ActionRow {
          width: parent.width
          title: "Pair with QR"; sub: "shg connect"; icon: "󰐷"
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.run("connect", ["connect"])
        }
        ActionRow {
          width: parent.width
          title: "Pair manually"; sub: "shg devices --wifi (code + address)"; icon: "󰑩"
          foreground: root.foreground; dim: root.dim
          cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
          onClicked: root.run("wifi", ["devices", "--wifi"])
        }

        PanelSectionHeader {
          text: root.hasProject ? "PROJECT ACTIONS" : "PROJECT ACTIONS (select a project)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          width: parent.width
        }

        Grid {
          width: parent.width
          columns: 2
          spacing: Style.space(8)
          opacity: root.hasProject ? 1 : 0.4
          enabled: root.hasProject
          readonly property real cellW: (width - spacing) / 2

          ActionRow { width: parent.cellW; title: "Build + Run"; sub: "shg build, shg run"; icon: "󰐊"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.run("build-run", ["deploy", "--all", "--variant", "debug"]) }
          ActionRow { width: parent.cellW; title: "Live reload"; sub: "shg dev --wifi"; icon: "󰑓"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.run("dev", ["dev", "--wifi"]) }
          ActionRow { width: parent.cellW; title: "Doctor"; sub: "Rescan issues"; icon: "󰓙"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.hostWidget.runDoctor() }
          ActionRow { width: parent.cellW; title: "Errors log"; sub: "Capacitor, level E"; icon: "󰌱"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.run("logs", ["device", "logs", "--tag", "Capacitor", "--level", "E"]) }
          ActionRow { width: parent.cellW; title: "Wake screen"; sub: "shg device wake"; icon: "󰛨"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: root.hostWidget.runQuiet(["device", "wake"], "Wake sent") }
          ActionRow { width: parent.cellW; title: "Android Studio"; sub: "shg open"; icon: "󰀲"
            foreground: root.foreground; dim: root.dim; cardFill: root.cardFill; cardBorder: root.cardBorder; fontFamily: root.fontFamily
            onClicked: { root.hostWidget.runQuiet(["open"], ""); root.close() } }
        }
      }
    }
  }

  // ----- local components -----
  component ActionRow: BorderSurface {
    id: row
    property string title: ""
    property string sub: ""
    property string icon: ""
    property color foreground: Color.foreground
    property color dim: Color.foreground
    property color cardFill: "transparent"
    property color cardBorder: "transparent"
    property string fontFamily: Style.font.family
    signal clicked()

    implicitHeight: Style.space(52)
    radius: Style.cornerRadius
    color: mouse.containsMouse
      ? Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.08) : row.cardFill
    borderSpec: Border.flat(row.cardBorder, 1)
    padding: Style.space(8)

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      spacing: Style.space(10)
      Text {
        text: row.icon
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        width: parent.width - Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
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
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
    }
  }

  component ProjectRow: BorderSurface {
    id: prow
    property string title: ""
    property string sub: ""
    property bool selected: false
    property bool recent: false
    property color foreground: Color.foreground
    property color dim: Color.foreground
    property color cardFill: "transparent"
    property color cardBorder: "transparent"
    property string fontFamily: Style.font.family
    signal clicked()
    signal forget()

    implicitHeight: Style.space(42)
    radius: Style.cornerRadius
    color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : (mouse.containsMouse ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08) : cardFill)
    borderSpec: Border.flat(selected ? Color.accent : cardBorder, 1)
    padding: Style.space(8)

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: prow.clicked()
    }
    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      spacing: Style.space(8)
      Text {
        text: prow.selected ? "●" : (prow.recent ? "󰋚" : "○")
        color: prow.selected ? Color.accent : prow.dim
        font.family: prow.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        width: parent.width - Style.space(26) - (prow.recent ? Style.space(28) : 0)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: prow.title
          color: prow.foreground
          font.family: prow.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: prow.sub
          color: prow.dim
          font.family: prow.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          width: parent.width
        }
      }
      PanelActionButton {
        visible: prow.recent
        iconText: "󰅖"
        tooltipText: "Remove from recents"
        foreground: prow.dim
        fontFamily: prow.fontFamily
        anchors.verticalCenter: parent.verticalCenter
        onClicked: prow.forget()
      }
    }
  }
}
