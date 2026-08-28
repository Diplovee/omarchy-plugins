function cToF(c) {
  return c * 9 / 5 + 32
}

function formatTemp(c, useF) {
  var v = Number(c)
  if (!isFinite(v)) return "—"
  if (useF) v = cToF(v)
  return Math.round(v) + "°" + (useF ? "F" : "C")
}

function formatTemp1(c, useF) {
  var v = Number(c)
  if (!isFinite(v)) return "—"
  if (useF) v = cToF(v)
  // one decimal for panel
  return (Math.round(v * 10) / 10).toFixed(1) + "°" + (useF ? "F" : "C")
}

function tempLevel(temp, warn, crit) {
  var t = Number(temp)
  var w = Number(warn), c = Number(crit)
  if (!isFinite(t)) return "cool"
  if (isFinite(c) && t >= c) return "crit"
  if (isFinite(w) && t >= w) return "hot"
  if (t >= 65) return "warm"
  return "cool"
}

function levelLabel(level) {
  if (level === "crit") return "Critical"
  if (level === "hot") return "Hot!"
  if (level === "warm") return "Warm"
  return "Cool"
}

function colorForLevel(level) {
  // hex strings; QML Qt.color will parse
  if (level === "crit") return "#e05a5a"
  if (level === "hot") return "#e8a65a"
  if (level === "warm") return "#e6d45a"
  return "#5ac87a"
}

function heatColor(temp, warn, crit) {
  return colorForLevel(tempLevel(temp, warn, crit))
}

function iconForLevel(level) {
  // Nerd Font thermometer + fire
  if (level === "crit") return "󰸁" // fire
  if (level === "hot") return "󰔏"
  if (level === "warm") return "󰔐"
  return "󰔏" // use same but color differs; could be 
}

function iconForTemp(temp, warn, crit) {
  return iconForLevel(tempLevel(temp, warn, crit))
}

function barFraction(temp, max) {
  var t = Number(temp), m = Number(max)
  if (!isFinite(t)) return 0
  if (!isFinite(m) || m <= 0) m = 100
  // clamp 0..1, use 100°C as full unless custom max higher
  var frac = t / m
  if (frac < 0) frac = 0
  if (frac > 1) frac = 1
  return frac
}

function displayTempForMode(sensors, mode, useF) {
  if (!Array.isArray(sensors) || sensors.length === 0) return "—"
  if (mode === "all") {
    // compact list CPU/GPU etc
    return sensors.slice(0, 3).map(function(s) { return formatTemp(s.temp, useF) }).join(" ")
  }
  if (mode === "cpu") {
    for (var i = 0; i < sensors.length; i++) {
      if (String(sensors[i].label).toLowerCase().indexOf("cpu") !== -1) return formatTemp(sensors[i].temp, useF)
    }
  }
  if (mode === "gpu") {
    for (var j = 0; j < sensors.length; j++) {
      if (String(sensors[j].label).toLowerCase().indexOf("gpu") !== -1) return formatTemp(sensors[j].temp, useF)
    }
  }
  // max
  var max = maxTemp(sensors)
  return formatTemp(max, useF)
}

function displayTempCForMode(sensors, mode) {
  if (!Array.isArray(sensors) || sensors.length === 0) return NaN
  if (mode === "cpu") {
    for (var i = 0; i < sensors.length; i++) if (String(sensors[i].label).toLowerCase().indexOf("cpu") !== -1) return sensors[i].temp
  }
  if (mode === "gpu") {
    for (var j = 0; j < sensors.length; j++) if (String(sensors[j].label).toLowerCase().indexOf("gpu") !== -1) return sensors[j].temp
  }
  return maxTemp(sensors)
}

function maxTemp(sensors) {
  if (!Array.isArray(sensors) || sensors.length === 0) return 0
  var m = -Infinity
  for (var i = 0; i < sensors.length; i++) {
    var t = Number(sensors[i].temp)
    if (isFinite(t) && t > m) m = t
  }
  return isFinite(m) ? m : 0
}

function tooltipText(sensors, useF) {
  if (!Array.isArray(sensors) || sensors.length === 0) return "No sensors"
  return sensors.map(function(s) {
    var name = String(s.label || s.id || "Sensor")
    return name + " " + formatTemp(s.temp, useF)
  }).join("  ·  ")
}

function parseSensorsJson(raw, useF) {
  // Try sensors -j format: { "k10temp-pci-00c3": { "Tctl": { "temp1_input": 71.7, "temp1_max": 100, ... } } }
  // We normalize to [{label, temp, max, crit}]
  var sensors = []
  var text = String(raw || "").trim()
  if (!text) return sensors
  // Check if it's our custom get_temps.py array JSON: starts with [
  if (text.charAt(0) === "[") {
    try {
      var arr = JSON.parse(text)
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          var e = arr[i]
          if (!e || e.temp === undefined) continue
          sensors.push({
            id: String(e.id || e.label || ("sensor-" + i)),
            label: String(e.label || e.id || "Sensor"),
            temp: Number(e.temp),
            max: e.max !== null && e.max !== undefined ? Number(e.max) : null,
            crit: e.crit !== null && e.crit !== undefined ? Number(e.crit) : null,
            source: String(e.source || "")
          })
        }
        return sensors
      }
    } catch (e) {}
  }
  // Attempt sensors -j parse
  try {
    var obj = JSON.parse(text)
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      for (var chip in obj) {
        var chipData = obj[chip]
        if (!chipData || typeof chipData !== "object") continue
        var friendlyChip = friendlyChipName(chip)
        for (var feat in chipData) {
          var featData = chipData[feat]
          if (!featData || typeof featData !== "object") continue
          // look for temp*_input keys
          for (var k in featData) {
            if (k.indexOf("temp") === 0 && k.indexOf("_input") !== -1) {
              var idx = k.replace("temp", "").replace("_input", "")
              var t = Number(featData[k])
              if (!isFinite(t)) continue
              var max = featData["temp" + idx + "_max"]
              var crit = featData["temp" + idx + "_crit"]
              var labelKey = "temp" + idx + "_label"
              var featLabel = featData[labelKey] || feat
              var label = friendlyChip
              if (featLabel && featLabel !== feat) label = label + " " + featLabel
              else if (feat !== chip && feat.toLowerCase().indexOf("temp") === -1) label = label + " " + feat
              sensors.push({
                id: chip + "-" + feat + "-" + idx,
                label: label,
                temp: t,
                max: isFinite(Number(max)) ? Number(max) : null,
                crit: isFinite(Number(crit)) ? Number(crit) : null,
                source: chip
              })
            }
          }
        }
      }
      if (sensors.length > 0) return sensors
    }
  } catch (e) {}
  // Fallback: hwmon lines format "name label temp max crit"
  // ignore
  return sensors
}

function friendlyChipName(chip) {
  var s = String(chip || "").toLowerCase()
  if (s.indexOf("k10temp") !== -1) return "CPU"
  if (s.indexOf("amdgpu") !== -1) return "GPU"
  if (s.indexOf("nvme") !== -1) return "SSD"
  if (s.indexOf("iwlwifi") !== -1) return "WiFi"
  if (s.indexOf("acpitz") !== -1) return "ACPI"
  if (s.indexOf("coretemp") !== -1) return "CPU"
  if (s.indexOf("zenpower") !== -1) return "CPU"
  // strip -pci-xxxx etc
  var dash = chip.indexOf("-")
  if (dash > 0) return chip.substring(0, dash)
  return chip
}

function friendlyHwmonName(name) {
  var n = String(name || "")
  if (n === "k10temp") return "CPU"
  if (n === "amdgpu") return "GPU"
  if (n === "nvme") return "SSD"
  if (n === "iwlwifi_1") return "WiFi"
  if (n === "acpitz") return "ACPI"
  return n
}

if (typeof module !== "undefined") {
  module.exports = {
    cToF: cToF,
    formatTemp: formatTemp,
    formatTemp1: formatTemp1,
    tempLevel: tempLevel,
    levelLabel: levelLabel,
    colorForLevel: colorForLevel,
    heatColor: heatColor,
    iconForLevel: iconForLevel,
    iconForTemp: iconForTemp,
    barFraction: barFraction,
    displayTempForMode: displayTempForMode,
    displayTempCForMode: displayTempCForMode,
    maxTemp: maxTemp,
    tooltipText: tooltipText,
    parseSensorsJson: parseSensorsJson,
    friendlyChipName: friendlyChipName,
    friendlyHwmonName: friendlyHwmonName
  }
}
