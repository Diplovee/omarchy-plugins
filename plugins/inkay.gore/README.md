# Gore Control (`inkay.gore`)

Lightweight Omarchy bar plugin for the Gore homelab server: online status,
health, and one-click Terminal / Herdr / Logs, plus confirmed reboot/shutdown.

Gore Control is a **convenience and observability layer over Gore, never a
dependency of Gore**. If the plugin breaks, `ssh gore` keeps working normally.

## Requirements

- Omarchy shell (Quickshell-based) with plugin support
- Working SSH: `ssh gore true` must succeed (key auth via `~/.ssh/config`;
  no passwords or keys are stored in this plugin)
- `nmcli` on the local machine (local-network gate)
- On Gore: `herdr` for the Herdr launcher, `journalctl` for logs
- Default terminal via `xdg-terminal-exec` (used through `omarchy-launch-*`)

## Installation

Source lives in this repo under `plugins/inkay.gore` (one standalone plugin
repo per `scripts/split-plugins.sh`), symlinked into the shell config:

```bash
ln -s ~/Projects/omarchy-plugins/plugins/inkay.gore ~/.config/omarchy/plugins/inkay.gore
omarchy-shell shell rescanPlugins
omarchy plugin enable inkay.gore
```

Validate the manifest without loading it:

```bash
omarchy plugin validate ~/Projects/omarchy-plugins/plugins/inkay.gore
```

> Note: hot-reload (`rescanPlugins`) does not always pick up widget code
> changes. If the widget seems stuck on old code, run
> `omarchy-restart-shell` for a clean reload.

### Installing `gore-status` on Gore

The plugin runs `ssh gore gore-status --json` (~every 5s). Install it to
Gore's `~/.local/bin` (already on Gore's non-interactive `PATH`):

```bash
scp plugins/inkay.gore/gore-status gore:.local/bin/gore-status
ssh gore gore-status --json   # should print one JSON object, exit 0
```

No root needed on either side. If `gore-status` is missing or broken, the
widget stays ONLINE and reports degraded health (`!`) instead of going offline.

## Architecture

Single `bar-widget` plugin (same pattern as Tailscale/Network/Thermal):

```text
BarWidget.qml  button + polling (nmcli gate -> ssh gore-status) + notifications
Panel.qml      popup: metrics, launchers, confirmed reboot/shutdown
GoreState.js   pure logic: states, debouncing, health eval, formatters
gore-status    server-side POSIX sh collector (JSON, exit 0/1/2 only)
manifest.json  plugin descriptor + config schema/defaults
```

One SSH connection per poll. Exit-code disambiguation (`gore-status` only
exits 0/1/2): `0` = reachable + parsed, `255` = SSH-level failure (counts
toward OFFLINE), anything else = reachable but status failed (degraded).

Connection states: `UNKNOWN → CONNECTING → ONLINE ⇄ DEGRADED → OFFLINE`,
plus `LOCAL_NETWORK_OFFLINE` (parked, never notified). Failure debouncing:
1 failure keeps ONLINE, threshold−1 → DEGRADED, threshold → OFFLINE.
Post-resume wall-clock jumps trigger a 12s grace period (no failure counting,
no notifications). Offline backoff: 1x/2x/3x/6x the poll interval (30s max).

Config lives inline on the `shell.json` bar entry
(`omarchy bar set inkay.gore <key> <value>`); keys: `host` (default `gore`,
never an IP), `displayName`, `pollIntervalSeconds`, `connectTimeoutSeconds`,
`offlineFailureThreshold`, `diskWarningPercent`, `notifyDisconnect`,
`notifyReconnect`, `notifyHealthProblems`.

Useful IPC: `omarchy-shell inkay.gore state|toggle|refresh`.

## Security model

- No stored credentials: no SSH keys, passwords, sudo passwords, or tokens.
- Auth is normal OpenSSH (`BatchMode=yes`, `StrictHostKeyChecking=yes` —
  never disabled).
- All process argv arrays are static; the hostname comes from config and is
  never shell-interpolated.
- Reboot/shutdown open a terminal running `sudo systemctl reboot|poweroff`
  on Gore — sudo policy is unchanged, password (if required) is typed there.
- Gore exposes nothing new: no ports, no daemons, one user-owned script.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Stuck on old code | `omarchy-restart-shell` (hot-reload is unreliable) |
| `○` offline, local wifi down | Expected: `LOCAL_NETWORK_OFFLINE`, retries automatically |
| `!` "not installed" | Re-install `gore-status` (see above) |
| `!` "Docker is not running" | `systemctl status docker` on Gore |
| No notifications | Check `notify*` settings; grace period suppresses post-resume ones |
| Panel opaque while bar is glassy | `[popups] background-alpha` in `~/.config/omarchy/shell.toml` |

## Uninstall

```bash
omarchy plugin disable inkay.gore
rm ~/.config/omarchy/plugins/inkay.gore
ssh gore 'rm ~/.local/bin/gore-status'   # optional: remove server script
```

`ssh gore` is unaffected before, during, and after.
