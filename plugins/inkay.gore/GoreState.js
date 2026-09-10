// GoreState.js — pure connection/health logic for the Gore Control widget.
//
// No QML or Quickshell imports here so the logic stays testable
// (e.g. `node -e "const S = require('./GoreState.js'); ..."`).
// The widget (BarWidget.qml) owns timers/processes and calls into this.

var CONN = {
  UNKNOWN: "UNKNOWN",
  CONNECTING: "CONNECTING",
  ONLINE: "ONLINE",
  DEGRADED: "DEGRADED",
  OFFLINE: "OFFLINE",
  LOCAL_NET: "LOCAL_NETWORK_OFFLINE"
}

function createState() {
  return {
    conn: CONN.UNKNOWN,
    prev: CONN.UNKNOWN,
    failures: 0,
    lastSuccessMs: 0,
    disconnectMs: 0,
    lastChangeMs: 0,
    // Health is orthogonal to connectivity: 'unknown' | 'healthy' | 'degraded'
    health: "unknown",
    healthReasons: []
  }
}

// Mark a poll starting. UNKNOWN -> CONNECTING so the widget shows ◐
// while the first check is in flight. Other states stay put.
function onPollStart(s) {
  if (s.conn === CONN.UNKNOWN) {
    s.prev = s.conn
    s.conn = CONN.CONNECTING
  }
}

// Local network gone: park in LOCAL_NET without touching the failure
// counter, so we don't blame Gore for a local outage. Returns true
// when the state changed.
function onLocalNetDown(s, nowMs) {
  if (s.conn === CONN.LOCAL_NET) return false
  s.prev = s.conn
  s.conn = CONN.LOCAL_NET
  s.lastChangeMs = nowMs
  return true
}

// Apply one SSH check result. threshold = failures required for OFFLINE.
// Debouncing: 1 failure keeps the current state, threshold-1 -> DEGRADED,
// threshold -> OFFLINE. Any success -> ONLINE.
// Returns { changed, prev, next }.
function onCheckResult(s, ok, nowMs, threshold) {
  var t = Math.max(1, Math.floor(Number(threshold) || 3))
  var prev = s.conn
  if (ok) {
    s.failures = 0
    s.lastSuccessMs = nowMs
    if (s.conn !== CONN.ONLINE) {
      s.prev = s.conn
      s.conn = CONN.ONLINE
      s.lastChangeMs = nowMs
    }
  } else {
    s.failures += 1
    var next = s.conn
    if (s.failures >= t) {
      next = CONN.OFFLINE
    } else if (t > 1 && s.failures === t - 1) {
      // Provisional issue: only escalate to DEGRADED when we had
      // something to lose (was online/connecting/degraded).
      if (s.conn === CONN.ONLINE || s.conn === CONN.CONNECTING
        || s.conn === CONN.DEGRADED || s.conn === CONN.UNKNOWN) {
        next = CONN.DEGRADED
      }
    }
    if (next !== s.conn) {
      s.prev = s.conn
      s.conn = next
      s.lastChangeMs = nowMs
      if (next === CONN.OFFLINE && s.disconnectMs === 0) s.disconnectMs = nowMs
    }
  }
  if (s.conn === CONN.ONLINE) s.disconnectMs = 0
  return { changed: s.conn !== prev, prev: prev, next: s.conn }
}

// Seconds since last success; -1 when never connected.
function secondsSinceSuccess(s, nowMs) {
  if (!s.lastSuccessMs) return -1
  return Math.max(0, Math.round((nowMs - s.lastSuccessMs) / 1000))
}

// Current outage length in ms (0 when not offline/degraded).
function outageMs(s, nowMs) {
  if (!s.disconnectMs) return 0
  if (s.conn !== CONN.OFFLINE && s.conn !== CONN.DEGRADED) return 0
  return Math.max(0, nowMs - s.disconnectMs)
}

// Wall-clock jump (laptop suspend, timer stall): true when the gap since
// the last poll far exceeds the expected interval. Callers use this to
// enter a post-resume grace period instead of blaming the server.
function resumedSince(lastWallMs, nowMs, expectedGapMs) {
  if (!lastWallMs) return false
  return (Number(nowMs) - Number(lastWallMs)) > Number(expectedGapMs)
}

// nmcli STATE output counts as usable local networking when it starts
// with "connected" (covers "connected", "connected (site only)", ...).
function localNetUsable(nmcliState) {
  return String(nmcliState || "").trim().toLowerCase().indexOf("connected") === 0
}
function displayFor(conn, health) {
  if (conn === CONN.ONLINE && health === "degraded") return { glyph: "!", label: "attention" }
  if (conn === CONN.ONLINE) return { glyph: "●", label: "online" }
  if (conn === CONN.CONNECTING || conn === CONN.DEGRADED) return { glyph: "◐", label: "connecting" }
  if (conn === CONN.LOCAL_NET) return { glyph: "○", label: "no network" }
  if (conn === CONN.OFFLINE) return { glyph: "○", label: "offline" }
  return { glyph: "○", label: "unknown" }
}

function plural(n, unit) {
  return n + unit
}

function formatUptimeSec(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  if (m > 0) return m + "m"
  return s + "s"
}

function formatDurationMs(ms) {
  var s = Math.max(0, Math.round((Number(ms) || 0) / 1000))
  if (s < 60) return plural(s, "s")
  var m = Math.floor(s / 60)
  if (m < 60) {
    var rest = s % 60
    return rest === 0 ? plural(m, "m") : m + "m " + rest + "s"
  }
  var h = Math.floor(m / 60)
  return h + "h " + (m % 60) + "m"
}

function formatBytes(bytes) {
  var b = Number(bytes)
  if (!isFinite(b) || b < 0) return "—"
  if (b < 1024) return Math.round(b) + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var i = -1
  do {
    b /= 1024
    i++
  } while (b >= 1024 && i < units.length - 1)
  return (Math.round(b * 10) / 10) + " " + units[i]
}

function timeAgoMs(ms, nowMs) {
  var diff = Math.max(0, (Number(nowMs) || 0) - (Number(ms) || 0))
  return formatDurationMs(diff) + " ago"
}

// Minimum shape for a usable status object. Guards against `{}` or
// truncated output parsing as "healthy" by accident.
function isValidStatus(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false
  if (!isFinite(Number(data.uptimeSeconds))) return false
  var mem = data.memory || {}
  if (!isFinite(Number(mem.totalBytes))) return false
  return true
}

// Parse `gore-status --json` output. Never throws.
function parseStatusJson(text) {
  var raw = String(text || "").trim()
  if (!raw) return { ok: false, error: "empty status output" }
  try {
    var data = JSON.parse(raw)
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      return { ok: false, error: "status JSON is not an object" }
    }
    return { ok: true, data: data }
  } catch (e) {
    return { ok: false, error: "malformed status JSON" }
  }
}

// Classify health per the v0.1 triggers. Never throws.
// Returns { health: 'healthy'|'degraded', reasons: [...] }.
function evaluateHealth(data, diskWarningPercent) {
  var reasons = []
  var warnAt = Number(diskWarningPercent)
  if (!isFinite(warnAt)) warnAt = 85
  if (!data || typeof data !== "object") {
    return { health: "degraded", reasons: ["status unavailable"] }
  }
  var services = data.services || {}
  if (services.docker !== undefined && services.docker !== "running") {
    reasons.push("Docker is not running.")
  }
  if (Number(data.failedSystemdUnits) > 0) {
    reasons.push(data.failedSystemdUnits + " failed systemd unit(s).")
  }
  var disk = data.disk || {}
  var pct = Number(disk.percent)
  if (isFinite(pct) && pct >= warnAt) {
    reasons.push("Disk usage " + Math.round(pct) + "%.")
  }
  return { health: reasons.length ? "degraded" : "healthy", reasons: reasons }
}

if (typeof module !== "undefined") {
  module.exports = {
    CONN: CONN,
    createState: createState,
    onPollStart: onPollStart,
    onLocalNetDown: onLocalNetDown,
    resumedSince: resumedSince,
    localNetUsable: localNetUsable,
    isValidStatus: isValidStatus,
    onCheckResult: onCheckResult,
    secondsSinceSuccess: secondsSinceSuccess,
    outageMs: outageMs,
    displayFor: displayFor,
    formatUptimeSec: formatUptimeSec,
    formatDurationMs: formatDurationMs,
    formatBytes: formatBytes,
    timeAgoMs: timeAgoMs,
    parseStatusJson: parseStatusJson,
    evaluateHealth: evaluateHealth
  }
}
