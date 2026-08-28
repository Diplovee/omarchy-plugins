import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "inkay.void"
  ipcTarget: "omarchy.void"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var hiddenWindows: voidModel.hiddenWindows
  property int selectedIndex: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null

  function normalizedIconKey(value) {
    return String(value || "").toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]/g, "")
  }

  function iconSourceFor(client) {
    if (!client || !root.appLibrary) return ""
    var classes = [client.initialClass, client.className]
    var aliases = []
    for (var c = 0; c < classes.length; c++) {
      var className = String(classes[c] || "")
      if (!className) continue
      aliases.push(className)
      var family = className.toLowerCase().split(/[-_.]/)[0]
      if (family === "chrome" || family === "chromium")
        aliases = aliases.concat(["chromium", "google-chrome", "googlechrome", "chrome"])
      else if (family === "firefox") aliases.push("firefox")
      else if (family === "code") aliases = aliases.concat(["code", "visual-studio-code", "visualstudiocode"])
    }

    var wanted = {}
    for (var a = 0; a < aliases.length; a++) wanted[normalizedIconKey(aliases[a])] = true
    var entries = DesktopEntries.applications.values || []
    var best = null
    var bestScore = 0
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || !entry.icon) continue
      var fields = [entry.id, entry.name, entry.startupWMClass, entry.wmClass]
      for (var f = 0; f < fields.length; f++) {
        var key = normalizedIconKey(fields[f])
        if (!key) continue
        var score = wanted[key] ? 100 : 0
        for (var w = 0; score === 0 && w < aliases.length; w++) {
          var aliasKey = normalizedIconKey(aliases[w])
          if (aliasKey && (key.indexOf(aliasKey) === 0 || aliasKey.indexOf(key) === 0) && Math.min(key.length, aliasKey.length) >= 3)
            score = 50
        }
        if (score > bestScore) {
          best = entry
          bestScore = score
        }
      }
    }
    if (best) return root.appLibrary.iconSource(String(best.icon))

    // Some apps expose only a WM class and no matching desktop entry. The
    // shared library still applies the current icon-theme lookup and generic
    // executable fallback for those cases.
    return root.appLibrary.iconSource(String(classes[0] || classes[1] || "application-x-executable"))
  }

  function open() {
    voidModel.refresh()
    root.controller.show()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function restore(address) { voidModel.restore(String(address || "")) }
  function restoreAll() { voidModel.restoreAll() }
  function hideFocused() { voidModel.hideFocused() }
  function refresh() { voidModel.refresh() }
  function selectDelta(delta) {
    if (root.hiddenWindows.length === 0) return
    var next = root.selectedIndex + Number(delta || 0)
    if (next < 0) next = 0
    if (next >= root.hiddenWindows.length) next = root.hiddenWindows.length - 1
    root.selectedIndex = next
  }
  function restoreSelected() {
    if (root.hiddenWindows.length === 0) return
    var entry = root.hiddenWindows[root.selectedIndex]
    if (entry) {
      root.restore(entry.address)
      root.close()
    }
  }

  // Layer-shell focus arrives asynchronously after the IPC open request. Keep
  // retrying briefly so an immediate Enter is not lost during that handoff.
  Timer {
    id: focusRetry
    interval: 25
    repeat: true
    running: root.opened
    onTriggered: if (keyCatcher && !keyCatcher.activeFocus) keyCatcher.forceActiveFocus()
  }

  onHiddenWindowsChanged: {
    if (root.hiddenWindows.length === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= root.hiddenWindows.length) root.selectedIndex = root.hiddenWindows.length - 1
  }
  onOpenedChanged: if (root.opened) root.selectedIndex = 0

  Main { id: voidModel }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.selectDelta(dy)
        else if (dx !== 0) root.selectDelta(dx)
      }
      onActivateRequested: root.restoreSelected()
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      Item {
        width: parent.width
        implicitHeight: titleColumn.implicitHeight

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: countLabel.left
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(2)

          Text {
            text: "Void"
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: "RUNNING WINDOWS IN SPECIAL:VOID"
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.1
          }
        }

        Text {
          id: countLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: String(root.hiddenWindows.length)
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }

      Text {
        visible: root.hiddenWindows.length === 0
        width: parent.width
        text: "Nothing is hidden.\nUse Super+Shift+H on a focused window."
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Column {
        id: windowList
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.hiddenWindows

          delegate: Item {
            required property var modelData
            required property int index
            width: windowList.width
            height: Style.space(58)
            implicitHeight: height

            Rectangle {
              id: rowSurface
              anchors.fill: parent
              radius: Style.cornerRadius / 2
              color: (rowMouse.containsMouse || root.selectedIndex === index)
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(10)

                Item {
                  width: Style.space(24)
                  height: Style.space(24)
                  anchors.verticalCenter: parent.verticalCenter

                  Image {
                    id: appIcon
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    source: root.iconSourceFor(modelData)
                    asynchronous: true
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.fill: parent
                    text: "󰖲"
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: !appIcon.visible
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(34)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: String(modelData.title || modelData.className || "Untitled window")
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: String(modelData.className || "Window") + "  ·  workspace " + String(modelData.workspaceName || modelData.workspaceId)
                    color: root.dim
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: {
                  root.restore(modelData.address)
                  root.close()
                }
              }
            }
          }
        }
      }

      Text {
        visible: root.hiddenWindows.length > 0
        width: parent.width
        text: "Click a window to restore it · Enter restores all"
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
