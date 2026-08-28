#!/usr/bin/env python3
import glob, json, os, sys

def read_float(path):
    try:
        with open(path) as f:
            return int(f.read().strip()) / 1000.0
    except:
        return None

def read_str(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return ""

# Friendly mapping for hwmon names
FRIENDLY = {
    "k10temp": "CPU",
    "coretemp": "CPU",
    "zenpower": "CPU",
    "amdgpu": "GPU",
    "nvme": "SSD",
    "iwlwifi_1": "WiFi",
    "iwlwifi": "WiFi",
    "acpitz": "ACPI",
    "BAT0": "Battery",
    "thinkpad": "ThinkPad",
}

sensors = []

# hwmon
for hw in glob.glob("/sys/class/hwmon/hwmon*"):
    name = read_str(os.path.join(hw, "name"))
    if not name:
        continue
    friendly_base = FRIENDLY.get(name, name)
    inputs = glob.glob(os.path.join(hw, "temp*_input"))
    # Skip duplicate nvme Sensor 1 (same as Composite, bogus max)
    if name == "nvme" and len(inputs) > 1:
        # keep only Composite (temp1) — temp2 is duplicate sensor with huge max
        inputs = [p for p in inputs if "temp1_input" in p]
    # also fan inputs for future?
    for inp in sorted(inputs):
        base = inp[:-6]  # strip _input
        # temp1_input -> base = .../temp1
        idx = os.path.basename(inp).replace("temp", "").replace("_input", "")
        temp = read_float(inp)
        if temp is None or temp == 0:
            # acpitz sometimes has 0 entries, skip
            continue
        # 0°C entries from disabled sensors
        if temp < -20 or temp > 200:
            continue
        label = read_str(base + "_label")
        # Build label with friendly mapping
        low_label = label.lower() if label else ""
        if low_label == "composite":
            sensor_label = "SSD"
        elif low_label == "edge":
            sensor_label = "GPU"
        elif "tctl" in low_label or "tdie" in low_label:
            sensor_label = "CPU"
        elif len(inputs) == 1:
            # single sensor, use friendly base as label
            sensor_label = friendly_base
            if label and label.lower() not in friendly_base.lower() and label.lower() not in ("composite", "edge"):
                sensor_label = f"{friendly_base} {label}"
        else:
            # multiple sensors, include label/index
            if label:
                # For ACPI without label, use index; for others use label
                if name == "acpitz" and not label:
                    sensor_label = f"ACPI {idx}"
                else:
                    sensor_label = f"{friendly_base} {label}"
            else:
                sensor_label = f"{friendly_base} {idx}"
        if low_label == "sensor 1" and name == "nvme":
            continue

        # Normalize duplicate ACPI labels: acpitz has multiple temp without label
        # They are already distinct by idx, okay.

        tmax = read_float(base + "_max")
        tcrit = read_float(base + "_crit")
        # Filter insane max
        if tmax is not None and (tmax < 20 or tmax > 200):
            tmax = None
        if tcrit is not None and (tcrit < 20 or tcrit > 200):
            tcrit = None
        # For acpitz, sometimes max is huge (65261), ignore
        if tmax is not None and tmax > 200:
            tmax = None

        sensors.append({
            "id": f"{name}-{idx}",
            "label": sensor_label,
            "temp": round(temp, 2),
            "max": round(tmax, 1) if tmax is not None else None,
            "crit": round(tcrit, 1) if tcrit is not None else None,
            "source": name
        })

# Deduplicate thermal zones that duplicate hwmon acpitz (optional - keep only hwmon)
# We already skip thermal zones to avoid duplicates. But include if hwmon had no acpitz?
if not any(s["source"] == "acpitz" for s in sensors):
    for tz in glob.glob("/sys/class/thermal/thermal_zone*"):
        typ = read_str(os.path.join(tz, "type"))
        if not typ or typ in ("x86_pkg_temp",):
            continue
        temp = read_float(os.path.join(tz, "temp"))
        if temp is None or temp == 0 or temp < -20 or temp > 200:
            continue
        # avoid duplicate of already captured
        label = typ
        # friendly
        if "acpi" in typ.lower():
            label = f"ACPI {typ}"
        sensors.append({
            "id": f"thermal-{typ}",
            "label": label,
            "temp": round(temp, 2),
            "max": None,
            "crit": None,
            "source": typ
        })

# Filter out sensors with 0 temp that are disabled (already)
# Sort: CPU first, GPU second, SSD, WiFi, ACPI last
order = {"CPU": 0, "GPU": 1, "SSD": 2, "WiFi": 3, "ACPI": 10}
def sort_key(s):
    lab = s["label"].split()[0]
    return (order.get(lab, 5), s["label"])
sensors.sort(key=sort_key)

# If no sensors, fallback try sensors -j via lm-sensors (not needed)
if not sensors:
    # try running sensors -j
    try:
        import subprocess, json as js
        out = subprocess.check_output(["sensors", "-j"], text=True, timeout=1)
        j = js.loads(out)
        # parse similar to Model.js but in python quickly
        for chip, data in j.items():
            friendly_base = FRIENDLY.get(chip.split("-")[0], chip.split("-")[0])
            # re-map chip friendly
            if "k10temp" in chip: friendly_base = "CPU"
            elif "amdgpu" in chip: friendly_base = "GPU"
            elif "nvme" in chip: friendly_base = "SSD"
            elif "iwlwifi" in chip: friendly_base = "WiFi"
            elif "acpitz" in chip: friendly_base = "ACPI"
            if not isinstance(data, dict):
                continue
            for feat, fdata in data.items():
                if not isinstance(fdata, dict):
                    continue
                for k, v in fdata.items():
                    if k.startswith("temp") and k.endswith("_input"):
                        idx = k.replace("temp","").replace("_input","")
                        try:
                            t = float(v)
                        except:
                            continue
                        lbl = fdata.get(f"temp{idx}_label", feat)
                        lab = friendly_base
                        if lbl and lbl != feat and "temp" not in lbl.lower():
                            lab = f"{friendly_base} {lbl}"
                        mx = fdata.get(f"temp{idx}_max")
                        cr = fdata.get(f"temp{idx}_crit")
                        sensors.append({
                            "id": f"{chip}-{feat}-{idx}",
                            "label": lab,
                            "temp": round(t,2),
                            "max": round(float(mx),1) if mx is not None else None,
                            "crit": round(float(cr),1) if cr is not None else None,
                            "source": chip
                        })
    except Exception:
        pass

# Output
json.dump(sensors, sys.stdout)
sys.stdout.write("\n")
