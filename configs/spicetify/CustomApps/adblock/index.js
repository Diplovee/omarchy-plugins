// Adblock - control surface for the adblock engine extension.
//
// The blocking itself lives in the extension (Extensions/adblock.js), which runs
// from startup. This app only renders the page and talks to that engine through
// localStorage (shared state) and two window events. Layout follows the
// Marketplace custom app so the sidebar entry matches it.

const react = Spicetify.React;

const ENABLED_KEY = "adblock-enabled";
const STATUS_KEY = "adblock-status";
const STAT_KEYS = {
  audio: "adblock-stats-audio",
  billboard: "adblock-stats-billboard",
  ui: "adblock-stats-ui",
};

function storedEnabled() {
  return localStorage.getItem(ENABLED_KEY) !== "false";
}

function storedStats() {
  const read = (key) => parseInt(localStorage.getItem(key) || "0", 10) || 0;
  return {
    audio: read(STAT_KEYS.audio),
    billboard: read(STAT_KEYS.billboard),
    ui: read(STAT_KEYS.ui),
  };
}

function storedEngineStatus() {
  try {
    return JSON.parse(localStorage.getItem(STATUS_KEY) || "null");
  } catch (e) {
    return null;
  }
}

// The engine owns the counters; mirror the intent through localStorage and let
// it re-read + re-apply immediately instead of shipping a second copy of state.
function writeEnabled(value) {
  localStorage.setItem(ENABLED_KEY, value ? "true" : "false");
  window.dispatchEvent(new CustomEvent("adblock:set-enabled", { detail: value }));
}

function writeStatsReset() {
  Object.values(STAT_KEYS).forEach((key) => localStorage.setItem(key, "0"));
  window.dispatchEvent(new CustomEvent("adblock:reset-stats"));
}

function yesNo(value) {
  if (value === true) return "yes";
  if (value === false) return "no";
  return "unknown";
}

function overrideText(value) {
  if (value === true) return "effective";
  if (value === false) return "ignored by this client - Spotify still serves ads";
  return "unknown";
}

class AdblockPage extends react.Component {
  constructor(props) {
    super(props);
    this.state = {
      enabled: storedEnabled(),
      stats: storedStats(),
      status: storedEngineStatus(),
    };
  }

  componentDidMount() {
    this.poll = setInterval(() => {
      this.setState({
        enabled: storedEnabled(),
        stats: storedStats(),
        status: storedEngineStatus(),
      });
    }, 1000);
  }

  componentWillUnmount() {
    clearInterval(this.poll);
  }

  toggle() {
    const next = !this.state.enabled;
    writeEnabled(next);
    this.setState({ enabled: next });
  }

  reset() {
    writeStatsReset();
    this.setState({ stats: { audio: 0, billboard: 0, ui: 0 } });
  }

  render() {
    const e = react.createElement;
    const stats = this.state.stats;
    const status = this.state.status || {};

    const statCard = (value, label) =>
      e(
        "div",
        { className: "adblock-stat-card" },
        e("span", { className: "adblock-stat-num" }, String(value)),
        e("span", { className: "adblock-stat-name" }, label)
      );

    const statusRow = (label, value) =>
      e(
        "div",
        { className: "adblock-status-row" },
        e("span", { className: "adblock-status-label" }, label),
        e("span", { className: "adblock-status-value" }, value)
      );

    return e(
      "section",
      { className: "contentSpacing adblock-page" },
      e(
        "div",
        { className: "adblock-page__intro" },
        e("h1", null, "Adblock"),
        e(
          "p",
          null,
          "Blocks premium upsell UI and redirects Spotify's ad delivery in this client. " +
            "The engine runs as a spicetify extension, so it is active from startup even " +
            "when this page is closed."
        )
      ),
      e(
        "div",
        { className: "adblock-page__card" },
        e(
          "div",
          { className: "adblock-toggle-row" },
          e("span", { className: "adblock-toggle-label" }, "Enable Adblocker"),
          e(
            "label",
            { className: "adblock-switch" },
            e("input", {
              type: "checkbox",
              checked: this.state.enabled,
              onChange: () => this.toggle(),
            }),
            e("span", { className: "adblock-slider" })
          )
        )
      ),
      e(
        "div",
        { className: "adblock-page__card" },
        e("div", { className: "adblock-stats-title" }, "Engine status"),
        statusRow("Audio ad manager disabled", yesNo(status.audioManagerDisabled)),
        statusRow("In-stream ad API disabled", yesNo(status.inStreamApiDisabled)),
        statusRow("Ad slots watched", String(status.slotsSubscribed || 0)),
        statusRow("Ad slots cleared", String(status.slotsCleared || 0)),
        statusRow(
          "Ad server redirected",
          status.adServerRedirected
            ? "yes - " + status.adServerSink
            : status.adServerRedirectError
            ? "no - " + status.adServerRedirectError
            : "no"
        ),
        statusRow("Premium state override", overrideText(status.adsOverrideEffective))
      ),
      e(
        "div",
        { className: "adblock-page__card" },
        e("div", { className: "adblock-stats-title" }, "Blocking statistics"),
        e(
          "div",
          { className: "adblock-stats-grid" },
          statCard(stats.audio, "Audio Ads"),
          statCard(stats.billboard, "Billboards"),
          statCard(stats.ui, "UI Elements")
        ),
        e(
          "button",
          { className: "adblock-btn-reset", onClick: () => this.reset() },
          "Reset statistics"
        )
      )
    );
  }
}

function render() {
  return react.createElement(AdblockPage, null);
}
