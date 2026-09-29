// ShgState.js — pure parsing/logic for the SHG Control widget (no QML imports,
// testable with node: `node -e "const S=require('./ShgState.js')"`).

var STATES = /^(device|offline|unauthorized|connecting|authorizing|recovery|sideload|bootloader|no permissions.*?)$/

// Parse `adb devices -l`. Wireless ids may contain spaces
// ("adb-XXXX-abc (3)._adb-tls-connect._tcp"), so match the state token from the
// right rather than splitting on whitespace.
function parseDevices(output) {
  var list = []
  var lines = String(output || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || /^List of devices/.test(line) || /^\*/.test(line)) continue
    var m = line.match(/^(.+?)\s+(device|offline|unauthorized|connecting|authorizing|recovery|sideload|bootloader|no permissions)\b(.*)$/)
    if (!m) continue
    var props = {}
    var re = /(\w+):(\S+)/g, p
    while ((p = re.exec(m[3])) !== null) props[p[1]] = p[2]
    var id = m[1].trim()
    list.push({
      id: id,
      state: m[2],
      model: (props.model || "").replace(/_/g, " "),
      wireless: id.indexOf(":") !== -1 || /_adb-tls-connect\._tcp/.test(id)
    })
  }
  return list
}

// Diff two device lists -> [{kind: "connected"|"disconnected", device}]
function diffDevices(prev, next) {
  var events = []
  function ready(l) { return l.filter(function(d) { return d.state === "device" }) }
  var a = ready(prev), b = ready(next)
  b.forEach(function(d) {
    if (!a.some(function(x) { return x.id === d.id })) events.push({ kind: "connected", device: d })
  })
  a.forEach(function(d) {
    if (!b.some(function(x) { return x.id === d.id })) events.push({ kind: "disconnected", device: d })
  })
  return events
}

// `shg doctor --json` -> issues (non-pass checks), worst first.
function parseDoctor(output) {
  var data
  try { data = JSON.parse(output) } catch (e) { return null }
  var checks = (data && data.checks) || []
  var rank = { fail: 0, error: 0, warn: 1, warning: 1 }
  return checks
    .filter(function(c) { return c.status !== "pass" && c.status !== "ok" })
    .sort(function(x, y) { return (x.status in rank ? rank[x.status] : 2) - (y.status in rank ? rank[y.status] : 2) })
}

function projectName(path) {
  var parts = String(path).replace(/\/+$/, "").split("/")
  return parts.length > 1 && /^(apps|packages)$/.test(parts[parts.length - 2])
    ? parts[parts.length - 3] + "/" + parts[parts.length - 1]
    : parts[parts.length - 1]
}

// Merge scanned paths with saved recents: recents first (by lastUsed desc), then scanned A-Z.
function mergeProjects(recents, scanned) {
  var seen = {}, out = []
  recents.slice().sort(function(a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0) })
    .forEach(function(r) { seen[r.path] = 1; out.push({ path: r.path, name: projectName(r.path), recent: true, lastUsed: r.lastUsed || 0 }) })
  scanned.slice().sort().forEach(function(p) {
    if (!seen[p]) out.push({ path: p, name: projectName(p), recent: false, lastUsed: 0 })
  })
  return out
}

function touchRecent(recents, path, now, max) {
  var out = recents.filter(function(r) { return r.path !== path })
  out.unshift({ path: path, lastUsed: now })
  return out.slice(0, max || 12)
}

function timeAgoMs(ts, now) {
  var s = Math.max(0, Math.round((now - ts) / 1000))
  if (s < 60) return s + "s ago"
  if (s < 3600) return Math.round(s / 60) + "m ago"
  if (s < 86400) return Math.round(s / 3600) + "h ago"
  return Math.round(s / 86400) + "d ago"
}

if (typeof module !== "undefined") {
  module.exports = { parseDevices: parseDevices, diffDevices: diffDevices, parseDoctor: parseDoctor,
    projectName: projectName, mergeProjects: mergeProjects, touchRecent: touchRecent, timeAgoMs: timeAgoMs }
}
