import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "inkay.thermal"
  ipcTarget: "inkay.thermal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Injected from host
  readonly property var sensors: hostWidget ? hostWidget.sensors : []
  readonly property real maxTemp: hostWidget ? hostWidget.maxTemp : 0
  readonly property var history: hostWidget ? hostWidget.history : []
  readonly property string displaySensor: hostWidget ? hostWidget.displaySensor : "max"
  readonly property bool useFahrenheit: hostWidget ? hostWidget.useFahrenheit : false
  readonly property int warnAt: hostWidget ? hostWidget.warnAt : 80
  readonly property int critAt: hostWidget ? hostWidget.critAt : 90
  readonly property string level: hostWidget ? hostWidget.level : Model.tempLevel(maxTemp, warnAt, critAt)
  readonly property string levelLabel: hostWidget ? hostWidget.levelLbl : Model.levelLabel(level)
  readonly property color heatColor: hostWidget ? hostWidget.heatColor : Model.heatColor(maxTemp, warnAt, critAt)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background

  // Collapse many ACPI sensors into summary + chevron
  property bool sensorsExpanded: false
  readonly property var primarySensors: {
    var out = []
    for (var i = 0; i < root.sensors.length; i++) {
      var s = root.sensors[i]
      var lab = String(s.label || "")
      if (lab.indexOf("ACPI") !== 0) out.push(s)
    }
    return out
  }
  readonly property var visibleSensors: root.sensorsExpanded ? root.sensors : root.primarySensors
  readonly property int hiddenCount: root.sensors.length - root.primarySensors.length

  function open() {
    if (hostWidget) hostWidget.refresh()
    root.controller.show()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function toggleUnit() {
    if (hostWidget && hostWidget.toggleUnit) hostWidget.toggleUnit()
    else if (root.bar && root.bar.shell) {
      var cur = root.settings.useFahrenheit === true
      var ns = Object.assign({}, root.settings, { useFahrenheit: !cur })
      root.bar.shell.updateEntryInline(root.moduleName, ns)
    }
  }

  function refresh() {
    if (hostWidget && hostWidget.refresh) hostWidget.refresh()
  }

  IpcHandler {
    target: "inkay.thermal"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function toggleSensors(): void { root.sensorsExpanded = !root.sensorsExpanded }
    function expandSensors(): void { root.sensorsExpanded = true }
    function collapseSensors(): void { root.sensorsExpanded = false }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(dir) { root.switchPanel(dir) }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)

      // Hero: icon + title + status + big temp
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTemp.implicitHeight)

        Text {
          id: heroIcon
          text: Model.iconForLevel(root.level)
          color: root.heatColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          Behavior on color { ColorAnimation { duration: 220 } }
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: heroTemp.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Thermal"
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            id: heroStatus
            text: root.levelLabel.toUpperCase() + (hostWidget ? "  ·  " + hostWidget.displaySensor.toUpperCase() : "")
            color: root.heatColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            Behavior on color { ColorAnimation { duration: 220 } }
          }
          Text {
            text: "warn " + root.warnAt + "°  ·  crit " + root.critAt + "°"
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: heroTemp
          text: root.sensors.length > 0 ? Model.formatTemp(root.maxTemp, root.useFahrenheit) : "—"
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }

      // Max heat bar (like battery bar)
      Item {
        width: parent.width
        implicitHeight: Style.space(8)
        Rectangle {
          id: heroTrack
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }
        Rectangle {
          id: heroFill
          anchors.left: heroTrack.left
          anchors.verticalCenter: heroTrack.verticalCenter
          height: heroTrack.height
          radius: heroTrack.radius
          color: root.heatColor
          width: Math.max(heroTrack.height, heroTrack.width * Model.barFraction(root.maxTemp, 100))
          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 220 } }
          SequentialAnimation on opacity {
            running: root.level === "crit" && root.opened
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
          }
        }
      }

      // Quick actions row - tip removed per request
      Row {
        id: quickRow
        width: parent.width
        spacing: Style.space(8)
        Button {
          id: unitBtn
          text: root.useFahrenheit ? "°F" : "°C"
          iconText: "󰔏"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.toggleUnit()
        }
        Button {
          id: refreshBtn
          text: "Refresh"
          iconText: "󰑐"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.refresh()
        }
      }

      PanelSeparator { foreground: root.foreground }

      // Sensors list header with chevron expand
      Item {
        width: parent.width
        implicitHeight: Math.max(sensorHeader.implicitHeight, expandBtn.implicitHeight)

        PanelSectionHeader {
          id: sensorHeader
          text: {
            if (root.hiddenCount > 0 && !root.sensorsExpanded)
              return "SENSORS  —  " + root.primarySensors.length + " shown  ·  " + root.hiddenCount + " ACPI hidden"
            return "SENSORS  —  " + root.sensors.length + " found"
          }
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          anchors.left: parent.left
          anchors.right: expandBtn.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
        }

        Button {
          id: expandBtn
          visible: root.hiddenCount > 0
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.sensorsExpanded ? "󰅂" : "󰅀"
          text: root.sensorsExpanded ? "Collapse" : "Show all"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(4)
          bordered: true
          onClicked: root.sensorsExpanded = !root.sensorsExpanded
        }

        MouseArea {
          anchors.fill: sensorHeader
          hoverEnabled: true
          cursorShape: root.hiddenCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (root.hiddenCount > 0) root.sensorsExpanded = !root.sensorsExpanded
        }
      }

      Column {
        id: sensorList
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: root.visibleSensors
          delegate: Item {
            required property var modelData
            required property int index
            width: sensorList.width
            implicitHeight: sensorColumn.implicitHeight

            Column {
              id: sensorColumn
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: Model.iconForTemp(modelData.temp, root.warnAt, root.critAt)
                  color: Model.heatColor(modelData.temp, root.warnAt, root.critAt)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: String(modelData.label || modelData.id)
                  color: root.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: index < 2
                  elide: Text.ElideRight
                  width: parent.width * 0.38
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: Model.formatTemp1(modelData.temp, root.useFahrenheit)
                  color: modelData.temp >= root.critAt ? root.heatColor : root.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  horizontalAlignment: Text.AlignRight
                  width: Style.space(68)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  visible: modelData.crit !== null || modelData.max !== null
                  text: {
                    var parts = []
                    if (modelData.max !== null) parts.push(Model.formatTemp(modelData.max, root.useFahrenheit))
                    if (modelData.crit !== null) parts.push(Model.formatTemp(modelData.crit, root.useFahrenheit))
                    // shorter: show as 78° / 82° with slash, tooltip would explain
                    return parts.join(" / ")
                  }
                  color: root.dim
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width * 0.24
                }
              }

              // Per-sensor bar
              Item {
                width: parent.width
                implicitHeight: 4
                Rectangle {
                  anchors.fill: parent
                  radius: height/2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height
                  radius: parent.height/2
                  width: Math.max(height, parent.width * Model.barFraction(modelData.temp, modelData.crit || modelData.max || 100))
                  color: Model.heatColor(modelData.temp, root.warnAt, root.critAt)
                  Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
                // max/crit markers
                Rectangle {
                  visible: modelData.max !== null
                  x: parent.width * Model.barFraction(modelData.max, modelData.crit || 100) - width/2
                  anchors.verticalCenter: parent.verticalCenter
                  width: 2; height: parent.height + 2
                  radius: 1
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                }
                Rectangle {
                  visible: modelData.crit !== null
                  x: parent.width * Model.barFraction(modelData.crit, modelData.crit) - width/2
                  anchors.verticalCenter: parent.verticalCenter
                  width: 2; height: parent.height + 6
                  radius: 1
                  color: "#e05a5a"
                  opacity: 0.95
                }
              }
            }
          }
        }

        // Summary hint when collapsed — shows hidden ACPI range
        Rectangle {
          visible: !root.sensorsExpanded && root.hiddenCount > 0
          width: parent.width
          implicitHeight: hintRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          border.width: 1

          Row {
            id: hintRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "󰅀"
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: {
                var hidden = []
                for (var i = 0; i < root.sensors.length; i++)
                  if (String(root.sensors[i].label).indexOf("ACPI") === 0) hidden.push(root.sensors[i].temp)
                if (hidden.length === 0) return root.hiddenCount + " hidden — click Show all"
                var mn = Math.min.apply(null, hidden)
                var mx = Math.max.apply(null, hidden)
                return root.hiddenCount + " ACPI hidden  ·  " + Model.formatTemp(mn, root.useFahrenheit) + " — " + Model.formatTemp(mx, root.useFahrenheit) + "  ·  click Show all"
              }
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: hintRow.width - 24
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.NoWrap
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sensorsExpanded = true
          }
        }

        Text {
          visible: root.sensors.length === 0
          text: "No sensors found. Install lm_sensors or check /sys/class/hwmon."
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }

      // History sparkline
      PanelSeparator { foreground: root.foreground; visible: root.history.length > 1 }

      Column {
        visible: root.history.length > 1
        width: parent.width
        spacing: Style.space(8)

        PanelSectionHeader {
          text: "HISTORY  —  last " + root.history.length + " polls (" + (root.hostWidget ? Math.round(root.hostWidget.pollMs/1000) + "s each" : "") + ")"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        // Range label above graph (avoids clipping when overlaid)
        Text {
          text: {
            if (root.history.length === 0) return ""
            var min = Math.min.apply(null, root.history)
            var max = Math.max.apply(null, root.history)
            return Model.formatTemp(min, root.useFahrenheit) + " — " + Model.formatTemp(max, root.useFahrenheit) + "  ·  " + root.history.length + " samples"
          }
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(48)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            border.width: 1
          }

          Row {
            id: sparkRow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Math.max(1, Math.min(3, (width / Math.max(1, root.history.length)) * 0.18))

            Repeater {
              model: root.history
              delegate: Item {
                required property var modelData
                required property int index
                width: Math.max(2, (sparkRow.width - sparkRow.spacing * (root.history.length - 1)) / Math.max(1, root.history.length))
                height: sparkRow.height

                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: {
                    var v = Number(modelData)
                    if (!isFinite(v)) return 2
                    var frac = Math.max(0, Math.min(1, v / 100))
                    return Math.max(3, parent.height * (0.18 + frac * 0.82))
                  }
                  radius: width/2
                  color: Model.heatColor(Number(modelData), root.warnAt, root.critAt)
                  opacity: index === root.history.length - 1 ? 1.0 : 0.85
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Bar color = " + root.levelLabel + " at " + Model.formatTemp(root.maxTemp, root.useFahrenheit) + "."
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }


    }
  }
}
