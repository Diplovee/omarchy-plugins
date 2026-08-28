import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "inkay.void"

  readonly property var panelObject: panelLoader.item
  readonly property int hiddenCount: panelObject ? panelObject.hiddenWindows.length : 0

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelObject) panelObject.open() }
  function close() { if (panelObject) panelObject.close() }
  function toggle() { if (panelObject) panelObject.toggle() }
  readonly property bool opened: panelObject ? panelObject.opened === true : false

  // Always visible so user can open the panel even when empty
  // (shows 0 and "Nothing is hidden" hint). Previously hidden when 0,
  // which made the feature undiscoverable.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  opacity: hiddenCount > 0 ? 1.0 : 0.55
  // Keep the slot reserved but dim when empty so the bar doesn't jump
  // when windows are hidden/restored. Remove `opacity` line if you prefer
  // a fully solid icon even when empty.

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
    target: "omarchy.void"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function restore(address: string): string {
      if (root.panelObject) root.panelObject.restore(address)
      return "ok"
    }
    function restoreAll(): string {
      if (root.panelObject) root.panelObject.restoreAll()
      return "ok"
    }
    function hideFocused(): string {
      if (root.panelObject) root.panelObject.hideFocused()
      return "ok"
    }
    function state(): string {
      return JSON.stringify({
        hiddenCount: root.hiddenCount,
        visible: root.visible,
        opacity: root.opacity,
        hasPanel: !!root.panelObject,
        panelHiddenCount: root.panelObject ? root.panelObject.hiddenWindows.length : -1
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰭚"
    tooltipText: "Void — " + root.hiddenCount + " hidden window" + (root.hiddenCount === 1 ? "" : "s")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.panelObject) root.panelObject.restoreAll()
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.panelObject) root.panelObject.refresh()
      } else root.toggle()
    }
  }
}
