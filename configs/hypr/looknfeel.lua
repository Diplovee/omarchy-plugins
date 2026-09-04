-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- rounding = 12 gives that modern rounded window look from your screenshot
hl.config({
  decoration = {
    rounding = 12,
    rounding_power = 2,
    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = "rgba(00000040)",
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      vibrancy = 0.1696,
      new_optimizations = true,
      ignore_opacity = true,
      xray = false,
      popups = true,
    },
  },
})

-- Make terminals transparent enough for blur to show (overrides default 0.985 0.96)
-- Matches kitty:background_opacity 0.85, foot:alpha 0.85, ghostty:background-opacity 0.85
o.window("kitty", { tag = "-default-opacity" })
o.window("kitty", { opacity = "0.92 0.85" })
o.window("foot", { tag = "-default-opacity" })
o.window("foot", { opacity = "0.92 0.85" })
o.window("com.mitchellh.ghostty", { tag = "-default-opacity" })
o.window("com.mitchellh.ghostty", { opacity = "0.92 0.85" })

-- Blur behind all layer surfaces (menu, bar, notifications, clipboard, etc) - makes glassy modern look
hl.layer_rule({ match = { namespace = "omarchy-.*" }, blur = true, ignore_alpha = 0.2, xray = false })
hl.layer_rule({ match = { namespace = "quickshell" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "notifications" }, blur = true, ignore_alpha = 0.2 })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
