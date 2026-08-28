import QtQuick
import Quickshell
import Quickshell.Io

// Session-only model for windows moved to Hyprland's special:void workspace.
// The bar widget owns one instance for the running shell session; no state is
// written to disk, so a logout/reboot naturally starts with an empty list.
Item {
  id: root

  property var hiddenWindows: []
  property var clients: []
  property string pendingClientAction: ""
  property string pendingClientArgument: ""
  property var pendingRestoreEntry: null
  property string pendingHyprAction: ""
  property var pendingHyprData: null
  property var hyprQueue: []
  property int restoreStep: 0
  property var restoreQueue: []
  property bool restoreBusy: false

  readonly property string voidWorkspace: "special:void"

  function addressOf(client) {
    return client && client.address ? String(client.address) : ""
  }

  function workspaceOf(client) {
    var workspace = client && client.workspace ? client.workspace : {}
    return {
      id: Number(workspace.id || 0),
      name: String(workspace.name || workspace.id || "")
    }
  }

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) }
    catch (e) { return fallback }
  }

  function syncClients(raw) {
    var parsed = parseJson(raw, [])
    if (!Array.isArray(parsed)) parsed = []
    clients = parsed

    // A client that no longer appears in hyprctl -j clients has closed. Keep
    // the saved workspace for live clients, while allowing title/class to
    // follow a window whose title changes while it is hidden.
    var live = {}
    for (var i = 0; i < parsed.length; i++) {
      var address = addressOf(parsed[i])
      if (address) live[address] = parsed[i]
    }

    var next = []
    for (var j = 0; j < hiddenWindows.length; j++) {
      var saved = hiddenWindows[j]
      var current = live[String(saved.address)]
      if (!current) continue
      var copy = {}
      for (var key in saved) copy[key] = saved[key]
      if (current.title !== undefined) copy.title = String(current.title || "")
      if (current.class !== undefined) copy.className = String(current.class || "")
      next.push(copy)
    }
    if (JSON.stringify(next) !== JSON.stringify(hiddenWindows)) hiddenWindows = next
  }

  function queryClients(action, argument) {
    if (action && action !== "refresh") {
      pendingClientAction = action
      pendingClientArgument = String(argument || "")
    } else if (!pendingClientAction) {
      pendingClientAction = "refresh"
      pendingClientArgument = ""
    }
    if (!clientsProcess.running) clientsProcess.running = true
  }

  function refresh() {
    if (!clientsProcess.running && !pendingClientAction) queryClients("refresh", "")
  }

  function hideFocused() {
    queryClients("hideFocused", "")
  }

  function focusedClient() {
    var fallback = null
    for (var i = 0; i < clients.length; i++) {
      var client = clients[i]
      if (!client || !addressOf(client)) continue
      var workspace = client.workspace || {}
      if (String(workspace.name || "") === root.voidWorkspace) continue
      if (Number(client.focusHistoryID) === 0) return client
      if (!fallback) fallback = client
    }
    return fallback
  }

  function saveHidden(client) {
    var address = addressOf(client)
    if (!address || isHidden(address)) return
    var workspace = workspaceOf(client)
    var entry = {
      address: address,
      workspaceId: workspace.id,
      workspaceName: workspace.name,
      title: String(client.title || ""),
      className: String(client.class || client.initialClass || ""),
      initialClass: String(client.initialClass || client.class || "")
    }
    var next = hiddenWindows.slice()
    next.push(entry)
    hiddenWindows = next
  }

  function isHidden(address) {
    var needle = String(address || "")
    for (var i = 0; i < hiddenWindows.length; i++)
      if (String(hiddenWindows[i].address) === needle) return true
    return false
  }

  function entryFor(address) {
    var needle = String(address || "")
    for (var i = 0; i < hiddenWindows.length; i++)
      if (String(hiddenWindows[i].address) === needle) return hiddenWindows[i]
    return null
  }

  function removeHidden(address) {
    var needle = String(address || "")
    hiddenWindows = hiddenWindows.filter(function(entry) {
      return String(entry.address) !== needle
    })
  }

  function restore(address) {
    var needle = String(address || "")
    if (!needle || !entryFor(needle)) return
    if (restoreBusy) {
      var queued = restoreQueue.slice()
      if (queued.indexOf(needle) === -1) queued.push(needle)
      restoreQueue = queued
      return
    }
    restoreBusy = true
    restoreQueue = [needle]
    processNextRestore()
  }

  function restoreAll() {
    var addresses = []
    for (var i = 0; i < hiddenWindows.length; i++) addresses.push(String(hiddenWindows[i].address))
    if (addresses.length === 0) return
    var next = restoreQueue.slice()
    for (var j = 0; j < addresses.length; j++)
      if (next.indexOf(addresses[j]) === -1) next.push(addresses[j])
    restoreQueue = next
    if (!restoreBusy) {
      restoreBusy = true
      processNextRestore()
    }
  }

  function processNextRestore() {
    if (restoreQueue.length === 0) {
      restoreBusy = false
      return
    }
    var next = restoreQueue.slice()
    var address = String(next.shift())
    restoreQueue = next
    if (!entryFor(address)) {
      processNextRestore()
      return
    }
    queryClients("restore", address)
  }

  function beginRestore(address) {
    var entry = entryFor(address)
    if (!entry) { processNextRestore(); return }
    pendingRestoreEntry = entry
    if (!workspaceProcess.running) workspaceProcess.running = true
  }

  function workspaceExists(workspaces, entry) {
    if (!Array.isArray(workspaces)) return false
    for (var i = 0; i < workspaces.length; i++) {
      var workspace = workspaces[i] || {}
      if (String(workspace.name || "") === String(entry.workspaceName || "")) return true
      if (Number(entry.workspaceId) !== 0 && Number(workspace.id) === Number(entry.workspaceId)) return true
    }
    return false
  }

  function chooseRestoreWorkspace(workspaces) {
    var entry = pendingRestoreEntry
    if (!entry) return
    var parsed = parseJson(workspaces, [])
    if (workspaceExists(parsed, entry)) {
      dispatchRestore(entry, String(entry.workspaceName || entry.workspaceId))
      return
    }
    // The original workspace may have disappeared after its last window was
    // hidden. Hyprland's active workspace is the requested fallback.
    activeWorkspaceProcess.running = true
  }

  function chooseFallbackWorkspace(raw) {
    var active = parseJson(raw, {})
    var workspace = String(active.name || active.id || "")
    if (workspace) dispatchRestore(pendingRestoreEntry, workspace)
    else finishRestore(false)
  }

  function dispatchRestore(entry, workspace) {
    if (!entry || !workspace) { finishRestore(false); return }
    restoreStep = 1
    runHypr("restoreFocus", { entry: entry, workspace: String(workspace) }, [
      "hyprctl", "dispatch",
      'hl.dsp.window.move({ window = "address:' + String(entry.address) + '", workspace = "' + String(workspace) + '", follow = false })'
    ])
  }

  function startHypr(action, data, command) {
    pendingHyprAction = action
    pendingHyprData = data
    hyprProcess.command = command
    hyprProcess.running = true
  }

  function runHypr(action, data, command) {
    if (hyprProcess.running) {
      var next = hyprQueue.slice()
      next.push({ action: action, data: data, command: command })
      hyprQueue = next
      return
    }
    startHypr(action, data, command)
  }

  function startNextHypr() {
    if (hyprProcess.running || hyprQueue.length === 0) return
    var next = hyprQueue.slice()
    var item = next.shift()
    hyprQueue = next
    startHypr(item.action, item.data, item.command)
  }

  function finishRestore(success) {
    var entry = pendingRestoreEntry
    pendingRestoreEntry = null
    if (success && entry) {
      removeHidden(entry.address)
    }
    processNextRestore()
  }

  Process {
    id: clientsProcess
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.clientsOutput = String(text || "")
    }
    onExited: root.clientsQueryFinished()
  }

  property string clientsOutput: ""

  function clientsQueryFinished() {
    var action = pendingClientAction
    var argument = pendingClientArgument
    pendingClientAction = ""
    pendingClientArgument = ""
    syncClients(clientsOutput)

    if (action === "hideFocused") {
      var client = focusedClient()
      if (client && !isHidden(addressOf(client))) {
        runHypr("hide", client, [
          "hyprctl", "dispatch",
          'hl.dsp.window.move({ workspace = "' + root.voidWorkspace + '", follow = false })'
        ])
      }
    } else if (action === "restore") {
      beginRestore(argument)
    }
  }

  Process {
    id: workspaceProcess
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.workspaceOutput = String(text || "")
    }
    onExited: root.chooseRestoreWorkspace(root.workspaceOutput)
  }

  property string workspaceOutput: ""

  Process {
    id: activeWorkspaceProcess
    command: ["hyprctl", "-j", "activeworkspace"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activeWorkspaceOutput = String(text || "")
    }
    onExited: root.chooseFallbackWorkspace(root.activeWorkspaceOutput)
  }

  property string activeWorkspaceOutput: ""

  Process {
    id: hyprProcess
    command: []
    onExited: function(code) { root.hyprCommandFinished(code) }
  }

  function hyprCommandFinished(exitCode) {
    var action = pendingHyprAction
    var data = pendingHyprData
    pendingHyprAction = ""
    pendingHyprData = null
    if (action === "hide") {
      if (exitCode === 0) saveHidden(data)
      refresh()
      startNextHypr()
    } else if (action === "restoreFocus") {
      if (exitCode !== 0 || !data || !data.entry) {
        finishRestore(false)
        startNextHypr()
      } else if (restoreStep === 1) {
        restoreStep = 2
        startHypr("restoreFocus", data, [
          "hyprctl", "dispatch",
          'hl.dsp.focus({ window = "address:' + String(data.entry.address) + '" })'
        ])
      } else if (restoreStep === 2) {
        restoreStep = 0
        finishRestore(true)
        startNextHypr()
      }
    } else {
      startNextHypr()
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()
}
