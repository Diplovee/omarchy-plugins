#!/bin/bash
# Zen - Omarchy theme sync hook
# Regenerates Zen userChrome.css from current Omarchy theme colors
# Called as: zen-omarchy-sync.sh <theme-name>

set -euo pipefail

COLORS_TOML="$HOME/.local/state/omarchy/current/theme/colors.toml"
if [[ ! -f "$COLORS_TOML" ]]; then
  exit 0
fi

# Extract colors from TOML (Aether format)
get_color() {
  grep -E "^$1\s*=" "$COLORS_TOML" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' | tr -d ' '
}

BACKGROUND=$(get_color background)
FOREGROUND=$(get_color foreground)
ACCENT=$(get_color accent)
SELECTION=$(get_color selection)
MUTED=$(get_color muted)
LIGHTER_BG=$(get_color lighter_background)
DARK_BG=$(get_color dark_background)

# Fallbacks if extraction fails
BACKGROUND=${BACKGROUND:-#00061e}
FOREGROUND=${FOREGROUND:-#EEF3F7}
ACCENT=${ACCENT:-#5682bb}
SELECTION=${SELECTION:-#1a1f35}
MUTED=${MUTED:-#5c5f64}
LIGHTER_BG=${LIGHTER_BG:-#1a1f35}
DARK_BG=${DARK_BG:-#000517}

# Find Zen profile (Default release)
ZEN_PROFILE_DIR=$(grep -E "^\[Profile" -A5 "$HOME/.config/zen/profiles.ini" 2>/dev/null | grep -E "Path=.*Default.*release" | head -1 | cut -d= -f2 | tr -d '\r')
if [[ -z "$ZEN_PROFILE_DIR" ]]; then
  ZEN_PROFILE_DIR="7w0lzr7l.Default (release)"
fi
CHROME_DIR="$HOME/.config/zen/$ZEN_PROFILE_DIR/chrome"
mkdir -p "$CHROME_DIR"

cat > "$CHROME_DIR/userChrome.css" <<EOF
/* Omarchy Zen - Auto-generated from $COLORS_TOML on \$(date) */
/* Theme: \${1:-unknown} - background $BACKGROUND, foreground $FOREGROUND, accent $ACCENT */

:root {
  --lwt-accent-color: $BACKGROUND !important;
  --lwt-text-color: $FOREGROUND !important;
  --arrowpanel-background: $BACKGROUND !important;
  --arrowpanel-color: $FOREGROUND !important;
  --arrowpanel-border-color: $ACCENT !important;
  --lwt-accent-color-inactive: $DARK_BG !important;
  --toolbar-bgcolor: $BACKGROUND !important;
  --toolbar-color: $FOREGROUND !important;
  --toolbar-non-lwt-bgcolor: $BACKGROUND !important;
  --toolbar-non-lwt-textcolor: $FOREGROUND !important;
  --toolbar-field-background-color: $SELECTION !important;
  --toolbar-field-color: $FOREGROUND !important;
  --toolbar-field-border-color: ${ACCENT}80 !important;
  --toolbar-field-focus-background-color: $SELECTION !important;
  --toolbar-field-focus-color: $FOREGROUND !important;
  --toolbar-field-focus-border-color: $ACCENT !important;
  --lwt-toolbar-field-highlight: $ACCENT !important;
  --lwt-toolbar-field-highlight-text: $BACKGROUND !important;
  --tab-selected-bgcolor: $SELECTION !important;
  --tab-selected-textcolor: $FOREGROUND !important;
  --lwt-selected-tab-background-color: $SELECTION !important;
  --tab-loading-fill: $ACCENT !important;
  --sidebar-background-color: $BACKGROUND !important;
  --sidebar-text-color: $FOREGROUND !important;
  --sidebar-border-color: ${ACCENT}40 !important;
  --chrome-content-separator-color: ${ACCENT}40 !important;
  --panel-background: $BACKGROUND !important;
  --panel-color: $FOREGROUND !important;
  --panel-border-color: $ACCENT !important;
  --zen-colors-primary: $BACKGROUND !important;
  --zen-colors-secondary: $SELECTION !important;
  --zen-colors-tertiary: $DARK_BG !important;
  --zen-colors-border: $ACCENT !important;
  --zen-primary-color: $ACCENT !important;
  --zen-colors-input-bg: $SELECTION !important;
  --zen-border-radius: 12px !important;
  --tab-border-radius: 10px !important;
  --toolbar-field-border-radius: 10px !important;
  --arrowpanel-border-radius: 12px !important;
  --panel-border-radius: 12px !important;
}

#nav-bar, #PersonalToolbar, #TabsToolbar {
  background-color: $BACKGROUND !important;
  color: $FOREGROUND !important;
  border-color: ${ACCENT}40 !important;
}

#urlbar, #searchbar {
  background-color: $SELECTION !important;
  color: $FOREGROUND !important;
  border-radius: 10px !important;
  border: 1px solid ${ACCENT}60 !important;
}

#urlbar[open], #urlbar:focus-within {
  background-color: $SELECTION !important;
  border-color: $ACCENT !important;
  box-shadow: 0 0 0 1px $ACCENT !important;
}

#urlbar-background, #searchbar {
  background-color: $SELECTION !important;
}

.tabbrowser-tab[selected="true"] .tab-background {
  background-color: $SELECTION !important;
  border: 1px solid ${ACCENT}80 !important;
  border-radius: 10px !important;
}

.tabbrowser-tab:not([selected="true"]) .tab-background {
  background-color: transparent !important;
  color: $MUTED !important;
}

.tabbrowser-tab:hover .tab-background {
  background-color: ${SELECTION}aa !important;
}

.tab-content[selected="true"] {
  color: $FOREGROUND !important;
}

#zen-sidebar, #sidebar-box, #sidebar {
  background-color: $BACKGROUND !important;
  color: $FOREGROUND !important;
  border-color: ${ACCENT}30 !important;
}

#zen-workspaces, .zen-workspace {
  background-color: transparent !important;
}

.zen-workspace-active {
  background-color: $SELECTION !important;
  border: 1px solid $ACCENT !important;
  border-radius: 10px !important;
}

#customization-panelWrapper > .panel-arrowcontent,
panel, menupopup, .panel-arrowcontent {
  background-color: $BACKGROUND !important;
  color: $FOREGROUND !important;
  border: 1px solid $ACCENT !important;
  border-radius: 12px !important;
}
EOF

cat > "$CHROME_DIR/userContent.css" <<EOF
/* Omarchy Zen - New Tab coordinated */
@-moz-document url("about:newtab"), url("about:home"), url("chrome://browser/content/browser.xhtml") {
  body, #newtab-window, #root {
    background-color: $BACKGROUND !important;
    color: $FOREGROUND !important;
  }
}

@-moz-document url-prefix("about:") {
  :root {
    --in-content-page-background: $BACKGROUND !important;
    --in-content-page-color: $FOREGROUND !important;
    --in-content-box-background: $SELECTION !important;
    --in-content-box-border-color: ${ACCENT}40 !important;
    --in-content-primary-button-background: $ACCENT !important;
    --in-content-primary-button-text-color: $BACKGROUND !important;
  }
  body {
    background-color: $BACKGROUND !important;
    color: $FOREGROUND !important;
  }
}

* {
  scrollbar-color: $ACCENT $BACKGROUND !important;
}
EOF

# Ensure user.js enables stylesheets
USER_JS="$HOME/.config/zen/$ZEN_PROFILE_DIR/user.js"
if ! grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$USER_JS" 2>/dev/null; then
  cat >> "$USER_JS" <<EJS

// Omarchy - enable userChrome
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);
EJS
fi

# Touch to trigger Zen reload on next launch (Zen reads userChrome on startup)
echo "Zen Omarchy theme synced to $BACKGROUND / $ACCENT for profile $ZEN_PROFILE_DIR"
