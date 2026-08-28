# my omarchy plugins

Personal [Omarchy](https://omarchy.org/) shell plugins by **inkay** — bar widgets built with [Quickshell](https://quickshell.org/).

> Monorepo for all third-party plugins. Each plugin is also publishable as a standalone `omarchy plugin add` repo.

## plugins

| Plugin | ID | Description |
|--------|----|-------------|
| **[thermal](plugins/inkay.thermal/)** | `inkay.thermal` | CPU/GPU/SSD/WiFi heat monitor. Bar shows hottest temp with a thin heat bar (green → yellow → orange → red). Click for breakdown, 5-ACPI collapsed by default, history sparkline, °C/°F toggle. |
| **[void](plugins/inkay.void/)** | `inkay.void` | Hide windows to `special:void` and restore on demand. Bar appears only when windows are hidden. |

### screenshots

**thermal** — bar: `󰔐 65°C` with heat underline (warm=yellow) · panel: hero 65°C + `Sensors — 4 shown · 5 ACPI hidden [Show all]` + per-sensor bars + history `65°C — 75°C · 11 samples`.

**void** — bar: `󰭚` with count tooltip · panel: list of hidden windows with icons.

## install

### from this monorepo (recommended for you)

```bash
git clone https://github.com/Diplovee/omarchy-plugins ~/Projects/omarchy-plugins
cd ~/Projects/omarchy-plugins
./install.sh            # symlinks plugins/inkay.* → ~/.config/omarchy/plugins/
# or manual:
cp -r plugins/inkay.thermal ~/.config/omarchy/plugins/
cp -r plugins/inkay.void ~/.config/omarchy/plugins/

# enable on bar
omarchy bar put inkay.thermal --after omarchy.power
omarchy bar put inkay.void --after omarchy.agents
omarchy-shell shell rescanPlugins
# or omarchy restart shell
```

### as standalone omarchy plugins

Each plugin is a valid `omarchy plugin` repo (manifest at root) when you push its directory as its own GitHub repo:

```bash
# thermal standalone
omarchy plugin add https://github.com/Diplovee/inkay.thermal --enable --yes
omarchy bar put inkay.thermal --after omarchy.power

# void standalone
omarchy plugin add https://github.com/Diplovee/inkay.void --enable --yes
```

This monorepo also includes `scripts/split-plugins.sh` to push each `plugins/*` as a subtree to its own repo.

## layout

```
omarchy-plugins/
├── README.md
├── LICENSE
├── install.sh
├── plugins/
│   ├── inkay.thermal/
│   │   ├── manifest.json   # omarchy plugin manifest
│   │   ├── BarWidget.qml
│   │   ├── Panel.qml
│   │   ├── Model.js
│   │   └── get_temps.py
│   └── inkay.void/
│       ├── manifest.json
│       ├── BarWidget.qml
│       ├── Panel.qml
│       └── Main.qml
└── scripts/
    └── split-plugins.sh
```

## development

Shell hot-reloads `~/.config/omarchy/plugins/` on save. Force a reload:

```bash
omarchy-shell shell rescanPlugins
omarchy-shell shell listPlugins | python3 -m json.tool | grep -A2 thermal
quickshell ipc -p /usr/share/omarchy/shell call inkay.thermal state | python3 -m json.tool
```

Edit in place, then sync back:

```bash
./scripts/sync-from-config.sh   # copies ~/.config/omarchy/plugins/inkay.* → plugins/
```

## thermal details

- Polls `~/.config/omarchy/plugins/inkay.thermal/get_temps.py` (hwmon + `/sys/class/thermal`) every 2s (`pollMs` in bar settings), falls back to `sensors -j`.
- Thresholds `warnAt=80` `critAt=90` configurable via bar widget settings (Omarchy Settings → Bar).
- Icons: `󰔏` cool / `󰔐` warm / `󰔏` hot / `󰸁` critical. Fill bar `width = temp / 100`.
- Panel: collapsed shows 4 primary (CPU/GPU/SSD/WiFi) + `5 ACPI hidden · 30°C — 65°C · click Show all` chevron; expanded shows 9. History 60 polls with sparkline. Right-click bar → toggle °F, middle-click → refresh.

## requirements

- Omarchy (Arch + Hyprland + Quickshell `omarchy-shell`)
- `lm_sensors` optional (hwmon fallback covers most systems)
- `python3` for `get_temps.py`

## license

MIT — see [LICENSE](LICENSE).
