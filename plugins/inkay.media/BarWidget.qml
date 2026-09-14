import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Media — now-playing bar widget with playback controls plus a seek and a
// volume slider (both live in Panel.qml, opened as a PopupCard).
//
// Self-contained on purpose: it talks to MPRIS itself instead of borrowing the
// first-party `omarchy.media` service, so it keeps working when that service is
// disabled. Quickshell reports MPRIS Position while a player is playing, so
// everything below binds to it directly and nothing polls.
BarWidget {
  id: root
  moduleName: "inkay.media"

  // ---------------------------------------------------------------- players

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // The player to drive: the first one playing a track, else the first one
  // holding track metadata at all.
  readonly property var activePlayer: {
    var list = root.players
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      if (!p.trackTitle && !p.trackArtist) continue
      if (p.isPlaying) return p
      if (fallback === null) fallback = p
    }
    return fallback
  }

  readonly property bool hasMedia: root.activePlayer !== null
  readonly property string title: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""
  readonly property string artist: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
  readonly property string album: root.activePlayer ? (root.activePlayer.trackAlbum || "") : ""
  readonly property string identity: root.activePlayer
    ? (root.activePlayer.identity || root.activePlayer.desktopEntry || "")
    : ""
  readonly property bool playing: root.activePlayer ? !!root.activePlayer.isPlaying : false
  readonly property string playIcon: root.playing ? "󰏤" : "󰐊"

  // ------------------------------------------------------------------- seek

  // Notified only when the player reports a non-linear jump (Quickshell
  // extrapolates between reports inside the getter), so this binding is kept
  // moving by positionTicker while the panel is showing it.
  readonly property real position: root.activePlayer ? root.activePlayer.position : 0
  readonly property real length: root.activePlayer && root.activePlayer.lengthSupported
    ? Math.max(0, root.activePlayer.length)
    : 0
  // MPRIS exposes two ways to seek: SetPosition (through the writable Position
  // property) and the relative Seek method. Prefer the absolute one.
  readonly property bool absoluteSeek: root.activePlayer
    ? (!!root.activePlayer.positionSupported && !!root.activePlayer.canControl)
    : false
  readonly property bool canSeek: root.activePlayer
    ? (root.absoluteSeek || (!!root.activePlayer.canSeek && root.length > 0))
    : false

  // ----------------------------------------------------------------- volume
  // MPRIS Volume when the player has a settable one; otherwise the default
  // PipeWire output, which is the sink the audio panel's slider drives.
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool playerVolume: root.activePlayer ? !!root.activePlayer.volumeSupported : false
  readonly property real volume: root.playerVolume
    ? (root.activePlayer ? root.activePlayer.volume : 0)
    : (root.sink && root.sink.audio ? root.sink.audio.volume : 0)
  readonly property bool canSetVolume: root.playerVolume || !!(root.sink && root.sink.audio)

  // --------------------------------------------------------------- controls

  function playPause() {
    var p = root.activePlayer
    if (!p) return false
    if (p.isPlaying && p.canPause) {
      p.pause()
      return true
    }
    if (!p.isPlaying && p.canPlay) {
      p.play()
      return true
    }
    if (p.canTogglePlaying) {
      p.togglePlaying()
      return true
    }
    return false
  }

  function next() {
    var p = root.activePlayer
    if (!p || !p.canGoNext) return false
    p.next()
    return true
  }

  function previous() {
    var p = root.activePlayer
    if (!p || !p.canGoPrevious) return false
    p.previous()
    return true
  }

  function seek(seconds) {
    var p = root.activePlayer
    if (!p) return false
    var target = Number(seconds)
    if (!isFinite(target)) return false
    if (root.length > 0) target = Math.min(target, root.length)
    target = Math.max(0, target)

    if (root.absoluteSeek) {
      p.position = target
      return true
    }
    if (p.canSeek) {
      p.seek(target - p.position)
      return true
    }
    return false
  }

  function setVolume(value) {
    var v = Number(value)
    if (!isFinite(v)) return false
    v = Math.max(0, Math.min(1, v))

    if (root.playerVolume) {
      root.activePlayer.volume = v
      return true
    }
    if (root.sink && root.sink.audio) {
      root.sink.audio.volume = v
      return true
    }
    return false
  }

  function round3(value) {
    var n = Number(value)
    return isFinite(n) ? Math.round(n * 1000) / 1000 : 0
  }

  // Reading `position` directly always returns the live value, unlike the
  // `position` property above, which only re-evaluates when the player
  // notifies (see the ticker at the bottom of this file).
  function livePosition() {
    var p = root.activePlayer
    return p ? p.position : 0
  }

  function statusJson() {
    var p = root.activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      identity: root.identity,
      title: root.title,
      artist: root.artist,
      album: root.album,
      playing: root.playing,
      position: root.round3(root.livePosition()),
      length: root.round3(root.length),
      volume: root.round3(root.volume),
      volumeSource: root.playerVolume ? "player" : "output",
      canSeek: root.canSeek,
      canSetVolume: root.canSetVolume
    })
  }

  function tooltipText() {
    if (!root.hasMedia) return "Media"
    return root.title + (root.artist ? " — " + root.artist : "") + "\n" + (root.playing ? "Playing" : "Paused")
  }

  // ------------------------------------------------------------------ panel

  readonly property var panelObject: panelLoader.item
  readonly property bool opened: root.panelObject ? root.panelObject.opened === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    panelLoader.active = true
    if (root.panelObject) {
      root.panelObject.open()
      return
    }
    // The Loader is asynchronous: a click right after the bar starts would
    // otherwise be dropped because there is no item yet.
    Qt.callLater(function() {
      if (root.panelObject) root.panelObject.open()
    })
  }

  function close() {
    if (root.panelObject) root.panelObject.close()
  }

  function toggle() {
    if (root.panelObject) root.panelObject.toggle()
    else root.open()
  }

  // ----------------------------------------------------------------- visual

  // Quickshell only emits positionChanged when the player's reported position
  // jumps; between reports it extrapolates inside the getter, so a binding on
  // `position` would sit still for the whole track. Re-emitting the signal
  // once a second — the way Quickshell's own docs describe monitoring the
  // position — is what keeps the panel's slider and elapsed label honest. It
  // runs only while the panel is open and something is actually playing, and
  // never faster than 1 Hz.
  readonly property bool positionWatched: root.opened && root.playing

  Timer {
    id: positionTicker
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.positionWatched
    onTriggered: if (root.activePlayer) root.activePlayer.positionChanged()
  }

  readonly property real maxLabelWidth: 180

  visible: root.hasMedia
  implicitWidth: root.hasMedia ? content.implicitWidth + Style.space(14) : 0
  implicitHeight: root.barSize

  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()

  IpcHandler {
    target: "inkay.media"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function next(): string { return root.next() ? "ok" : "unhandled" }
    function previous(): string { return root.previous() ? "ok" : "unhandled" }
    function seekSeconds(seconds: real): string { return root.seek(seconds) ? "ok" : "unhandled" }
    function volumePercent(percent: real): string { return root.setVolume(Number(percent) / 100) ? "ok" : "unhandled" }
    function status(): string { return root.statusJson() }
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

  // One interactive surface for the whole widget: WidgetButton owns the bar's
  // click routing (and its tooltip), so left/middle/right and the wheel all
  // arrive here instead of being eaten by the bar's own slot handler.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.next()
      else if (buttonCode === Qt.RightButton) root.toggle()
      else root.playPause()
    }
    onWheelMoved: function(delta) {
      if (delta > 0) root.previous()
      else if (delta < 0) root.next()
    }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: root.playing
        ? (root.bar ? root.bar.barForeground : Color.foreground)
        : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.title !== ""

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          running: labelText.needsScroll && !root.opened && !root.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }
}
