import QtQuick
import qs.Commons
import qs.Ui

// Media panel — artwork, track text, transport buttons, and the two sliders
// this widget exists for: seek (bound to the player's position/length) and
// volume (the player's MPRIS volume, or the default output when the player
// has none).
//
// The root is a plain Item rather than the PopupCard itself because the host
// widget injects `bar` and `anchorItem` only after the Loader has created us,
// and PopupCard's own properties are required — they must not be missing at
// instantiation time.
Item {
  id: root

  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null

  // The bar widget owns the MPRIS and audio state; the panel only renders and
  // calls back into it, so IPC and UI always act on the same player.
  readonly property var media: root.hostWidget
  readonly property var player: root.media ? root.media.activePlayer : null
  readonly property string title: root.player ? (root.player.trackTitle || "") : ""
  readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
  readonly property string album: root.player ? (root.player.trackAlbum || "") : ""
  readonly property string artUrl: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
  readonly property bool playing: root.player ? !!root.player.isPlaying : false
  readonly property real position: root.media ? root.media.position : 0
  readonly property real length: root.media ? root.media.length : 0
  readonly property bool canSeek: root.media ? root.media.canSeek : false
  readonly property real volume: root.media ? root.media.volume : 0
  readonly property bool canSetVolume: root.media ? root.media.canSetVolume : false
  readonly property bool playerVolume: root.media ? root.media.playerVolume : false

  readonly property color foreground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(root.foreground, 1.3)
  readonly property color dimmer: Qt.darker(root.foreground, 1.6)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property alias opened: card.open

  function open() { card.open = true }
  function close() { card.open = false }
  function toggle() { card.open = !card.open }

  // MPRIS lengths are double seconds; render them as m:ss (h:mm:ss past an
  // hour). A player that reports no length has nothing to show.
  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var s = total % 60
    var m = Math.floor(total / 60) % 60
    var h = Math.floor(total / 3600)
    function pad(value) { return value < 10 ? "0" + value : String(value) }
    return (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(s)
  }

  function seekLabel() {
    var at = root.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.position)
    return at + "  /  " + (root.length > 0 ? root.formatTime(root.length) : "--:--")
  }

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: false
    contentWidth: card.fittedContentWidth(Style.space(340))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: root.artUrl === ""
            text: "󰝚"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.album
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: !!root.player && root.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.media) root.media.previous()
        }

        Button {
          iconText: root.playing ? "󰏤" : "󰐊"
          foreground: root.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: !!root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.media) root.media.playPause()
        }

        Button {
          iconText: "󰒭"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: !!root.player && root.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.media) root.media.next()
        }
      }

      PanelSeparator {
        foreground: root.foreground
      }

      Column {
        id: seekSection
        width: parent.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: Math.max(seekHeader.implicitHeight, seekTimes.implicitHeight)

          PanelSectionHeader {
            id: seekHeader
            text: "SEEK"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: seekTimes
            textFormat: Text.PlainText
            text: root.seekLabel()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.canSeek ? 1.0 : 0.5
          }
        }

        PanelSlider {
          id: seekSlider
          bar: root.bar
          width: parent.width
          minimum: 0
          maximum: Math.max(1, root.length)
          step: Math.max(1, root.length / 100)
          // Dragging drives the label from liveValue; the player is only asked
          // to move once, when the drag ends.
          value: root.position
          enabled: root.canSeek
          opacity: root.canSeek ? 1.0 : 0.5
          onReleased: function(value) { if (root.media) root.media.seek(value) }
        }
      }

      Column {
        id: volumeSection
        width: parent.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: Math.max(volumeHeader.implicitHeight, volumePercent.implicitHeight)

          PanelSectionHeader {
            id: volumeHeader
            text: root.playerVolume ? "VOLUME" : "OUTPUT VOLUME"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: volumePercent
            textFormat: Text.PlainText
            text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.volume) * 100) + "%"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.canSetVolume ? 1.0 : 0.5
          }
        }

        PanelSlider {
          id: volumeSlider
          bar: root.bar
          width: parent.width
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.volume
          enabled: root.canSetVolume
          opacity: root.canSetVolume ? 1.0 : 0.5
          // Applied as it moves, the way the audio panel's sliders behave —
          // the player only sees cheap dBus writes.
          onMoved: function(value) { if (root.media) root.media.setVolume(value) }
        }
      }
    }
  }
}
