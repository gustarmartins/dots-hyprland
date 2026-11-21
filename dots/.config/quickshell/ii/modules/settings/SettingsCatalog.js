// Audited against Config.qml and runtime consumers. Run tests/settings_catalog.py
// when Config.qml changes: every key must be exposed, managed, or retired.
.pragma library
var timeUnits = {"ms": "milliseconds", "s": "seconds", "min": "minutes"};
var pages = [
  {
    "id": "design",
    "title": "Design",
    "icon": "palette",
    "description": "Color, animation, GPU effects and typography — one place to shape your desktop."
  },
  {"id":"storage", "title":"Disk space & cleanup", "icon":"hard_drive", "description":"Available space, early warnings, build caches and trash."},
  {"id":"company", "title":"Company accounts", "icon":"manage_accounts", "description":"PC reconnection alerts, password recovery and private audit history."},
  {
    "id": "home",
    "title": "Your desktop",
    "icon": "space_dashboard",
    "description": "A place for every part of your desktop."
  },
  {
    "id": "wallpaper",
    "title": "Wallpapers",
    "icon": "wallpaper",
    "description": "Discovery, rotation and offline downloads. Open the library to preview or restore images."
  },
  {
    "id": "bar",
    "title": "Bar & resources",
    "icon": "dock_to_bottom",
    "description": "Position, tray, workspace indicators and resource monitoring."
  },
  {
    "id": "control",
    "title": "Control center",
    "icon": "tune",
    "description": "Tiles, sliders and the corners that open your sidebars."
  },
  {
    "id": "workspaces",
    "title": "Workspaces & dock",
    "icon": "view_carousel",
    "description": "Overview layout, pinned applications and the dock."
  },
  {
    "id": "widgets",
    "title": "Desktop widgets",
    "icon": "widgets",
    "description": "Clock and weather placement on every monitor."
  },
  {
    "id": "notifications",
    "title": "Notifications",
    "icon": "notifications",
    "description": "Popup delivery, unread counts and on-screen feedback."
  },
  {
    "id": "mail",
    "title": "Mail",
    "icon": "mail",
    "description": "Accounts, message previews, verification codes and links."
  },
  {
    "id": "capture",
    "title": "Capture & overlays",
    "icon": "screenshot_region",
    "description": "Screenshots, Lens, annotations and floating overlays."
  },
  {
    "id": "launcher",
    "title": "Launcher & apps",
    "icon": "search",
    "description": "Search behavior, prefixes and the apps used by shell actions."
  },
  {
    "id": "audio",
    "title": "Audio & night light",
    "icon": "volume_up",
    "description": "Music loudness, quiet songs, gain, spatial audio, volume protection and evening color."
  },
  {
    "id": "general",
    "title": "Time & language",
    "icon": "language",
    "description": "Clocks, sounds, interface language and feature preferences."
  },
  {
    "id": "session",
    "title": "Lock & power",
    "icon": "lock",
    "description": "Lock-screen appearance, authentication and battery behavior."
  },
  {
    "id": "services",
    "title": "Sidebar services",
    "icon": "chat",
    "description": "Assistant models, translation and image-search preferences."
  },
  {"id":"agents", "title":"AI sessions", "icon":"terminal", "description":"Identify agent sessions, terminal PIDs and heavy child workloads."},
  {"id":"memory", "title":"Memory locks", "icon":"memory", "description":"Keep important apps responsive. Review RAM use and choose which processes to protect from swap."},
  {
    "id": "advanced",
    "title": "Advanced",
    "icon": "settings",
    "description": "Interaction tuning, privacy rules and alternate shell options."
  },
  {"id":"cryod", "title":"CryoD", "icon":"memory", "description":"Performance master, CPU priority, optional GPU/latency boost, foreground protection and app freezing preferences."},
  {
    "id": "about",
    "title": "About",
    "icon": "info",
    "description": "Fork documentation and support."
  }
];

var entries = [
    {"path": "panelFamily", "page": "advanced", "section": "Alternate shell", "title": "Shell layout", "kind": "choice", "description": "Select the main layout. Waffle-specific controls below apply only to Waffle.", "choices": [{"value": "ii", "label": "illogical impulse"}, {"value": "waffle", "label": "Waffle"}]},
    {"path": "policies.ai", "page": "general", "section": "Feature preferences", "title": "AI features", "kind": "choice", "min": 0, "max": 10000, "step": 1, "scale": 1, "choices": [{"value": 0, "label": "Off"}, {"value": 1, "label": "Enabled"}, {"value": 2, "label": "Local only"}]},
    {"path": "policies.weeb", "page": "general", "section": "Feature preferences", "title": "Anime content", "kind": "choice", "min": 0, "max": 10000, "step": 1, "scale": 1, "choices": [{"value": 0, "label": "Hidden"}, {"value": 1, "label": "Enabled"}, {"value": 2, "label": "Private"}]},
    {"path": "ai.systemPrompt", "page": "services", "section": "Sidebar assistant", "title": "Assistant instructions", "kind": "longtext", "description": "Saved only when you finish editing or press Save."},
    {"path": "ai.tool", "page": "services", "section": "Sidebar assistant", "title": "Assistant tool", "kind": "choice", "choices": [{"value": "functions", "label": "Functions"}, {"value": "search", "label": "Search"}, {"value": "none", "label": "None"}]},
    {"path": "ai.extraModels", "page": "services", "section": "Sidebar assistant", "title": "Additional assistant models", "kind": "json", "description": "Advanced model definitions as a JSON array. API keys are configured in the assistant sidebar."},
    {"path": "appearance.extraBackgroundTint", "page": "design", "section": "Surface appearance", "title": "Extra background tint", "kind": "toggle"},
    {"path": "appearance.fakeScreenRounding", "page": "design", "section": "Surface appearance", "title": "Fake screen rounding", "kind": "choice", "min": 0, "max": 10000, "step": 1, "scale": 1, "choices": [{"value": 0, "label": "Off"}, {"value": 1, "label": "Always"}, {"value": 2, "label": "Except fullscreen"}]},
    {"path": "appearance.fontSizes.ui", "page": "design", "section": "Shell base sizes (pt)", "title": "Interface size", "kind": "number", "description": "Points. Zero keeps the original shell size; other labels scale proportionally.", "min": 0, "max": 48, "step": 0.5, "scale": 1},
    {"path": "appearance.fontSizes.mono", "page": "design", "section": "Shell base sizes (pt)", "title": "Monospace size", "kind": "number", "description": "Points. Zero keeps the original shell size.", "min": 0, "max": 48, "step": 0.5, "scale": 1},
    {"path": "appearance.fontSizes.title", "page": "design", "section": "Shell base sizes (pt)", "title": "Heading size", "kind": "number", "description": "Points. Zero keeps the original shell size.", "min": 0, "max": 48, "step": 0.5, "scale": 1},
    {"path": "appearance.fonts.main", "page": "design", "section": "Shell font families", "title": "Interface family", "kind": "text", "description": "Shell labels and menus. Desktop-wide changes belong to the profile picker above."},
    {"path": "appearance.fonts.numbers", "page": "design", "section": "Shell font families", "title": "Numbers family", "kind": "text", "description": "Clocks and numeric labels."},
    {"path": "appearance.fonts.title", "page": "design", "section": "Shell font families", "title": "Heading family", "kind": "text", "description": "Section titles and shell window titles."},
    {"path": "appearance.fonts.iconNerd", "page": "design", "section": "Shell font families", "title": "Nerd Font family", "kind": "text", "description": "Keep a Nerd Font here so application and distro glyphs remain available."},
    {"path": "appearance.fonts.monospace", "page": "design", "section": "Shell font families", "title": "Monospace family", "kind": "text", "description": "Code and technical values inside the shell."},
    {"path": "appearance.fonts.reading", "page": "design", "section": "Shell font families", "title": "Reading family", "kind": "text", "description": "Longer body text."},
    {"path": "appearance.fonts.expressive", "page": "design", "section": "Shell font families", "title": "Expressive family", "kind": "text", "description": "Decorative text and large accents."},
    {"path": "appearance.transparency.enable", "page": "design", "section": "Shell transparency", "title": "Enable shell transparency", "kind": "toggle", "description": "GPU blur and window opacity are grouped above."},
    {"path": "appearance.transparency.automatic", "page": "design", "section": "Shell transparency", "title": "Automatic shell transparency", "kind": "toggle", "description": "Let the shell derive transparency from the current theme."},
    {"path": "appearance.transparency.backgroundTransparency", "page": "design", "section": "Shell transparency", "title": "Background transparency", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "when": [["appearance.transparency.enable", true], ["appearance.transparency.automatic", false]]},
    {"path": "appearance.transparency.contentTransparency", "page": "design", "section": "Shell transparency", "title": "Content transparency", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "when": [["appearance.transparency.enable", true], ["appearance.transparency.automatic", false]]},
    {"path": "appearance.wallpaperTheming.enableAppsAndShell", "page": "design", "section": "Apply colors to applications", "title": "Theme shell and applications", "kind": "toggle", "apply": "colors", "description": "Regenerate the shell palette and supported application colors."},
    {"path": "appearance.wallpaperTheming.enableQtApps", "page": "design", "section": "Apply colors to applications", "title": "Theme Qt applications", "kind": "toggle", "apply": "colors", "description": "Requires application theming to be enabled above.", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true]]},
    {"path": "appearance.wallpaperTheming.enableTerminal", "page": "design", "section": "Apply colors to applications", "title": "Theme terminals", "kind": "toggle", "apply": "colors", "description": "Regenerate the terminal palette from the current wallpaper.", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true]]},
    {"path": "appearance.wallpaperTheming.terminalGenerationProps.harmony", "page": "design", "section": "Terminal palette", "title": "Terminal wallpaper tint", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "apply": "colors", "description": "0% preserves canonical ANSI hues; higher values tint toward the wallpaper accent.", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true], ["appearance.wallpaperTheming.enableTerminal", true]]},
    {"path": "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold", "page": "design", "section": "Terminal palette", "title": "Maximum terminal hue shift", "kind": "number", "suffix": "°", "min": 0, "max": 101, "step": 1, "scale": 1, "apply": "colors", "description": "Limits how far wallpaper tint can move each ANSI hue.", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true], ["appearance.wallpaperTheming.enableTerminal", true]]},
    {"path": "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost", "page": "design", "section": "Terminal palette", "title": "Terminal contrast", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "apply": "colors", "description": "Moves ANSI tones away from the background while preserving color families.", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true], ["appearance.wallpaperTheming.enableTerminal", true]]},
    {"path": "appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode", "page": "design", "section": "Terminal palette", "title": "Force dark terminal palette", "kind": "toggle", "apply": "colors", "when": [["appearance.wallpaperTheming.enableAppsAndShell", true], ["appearance.wallpaperTheming.enableTerminal", true]]},
    {"path": "appearance.palette.type", "page": "design", "section": "Color palette", "title": "Palette style", "kind": "choice", "choices": [{"value": "auto", "label": "Auto"}, {"value": "scheme-content", "label": "Content"}, {"value": "scheme-expressive", "label": "Expressive"}, {"value": "scheme-fidelity", "label": "Fidelity"}, {"value": "scheme-fruit-salad", "label": "Fruit Salad"}, {"value": "scheme-monochrome", "label": "Monochrome"}, {"value": "scheme-neutral", "label": "Neutral"}, {"value": "scheme-rainbow", "label": "Rainbow"}, {"value": "scheme-tonal-spot", "label": "Tonal Spot"}, {"value": "scheme-vibrant", "label": "Vibrant"}], "apply": "colors", "description": ""},
    {"path": "appearance.palette.accentColor", "page": "design", "section": "Color palette", "title": "Custom accent color", "kind": "text", "apply": "colors", "description": "Leave empty to use the wallpaper. Use a color such as #a5b4fc.", "validation": "color"},
    {"path": "audio.protection.enable", "page": "audio", "section": "Volume protection", "title": "Enable volume protection", "kind": "toggle", "description": "Limits sudden volume increases and the maximum output level."},
    {"path": "audio.protection.maxAllowedIncrease", "page": "audio", "section": "Volume protection", "title": "Max allowed increase", "kind": "number", "min": 0, "max": 101, "step": 1, "scale": 1},
    {"path": "audio.protection.maxAllowed", "page": "audio", "section": "Volume protection", "title": "Volume limit", "kind": "number", "min": 0, "max": 101, "step": 1, "scale": 1},
    {"path": "apps.bluetooth", "page": "launcher", "section": "Preferred applications", "title": "Bluetooth", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.changePassword", "page": "launcher", "section": "Preferred applications", "title": "Password settings", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.network", "page": "launcher", "section": "Preferred applications", "title": "Network", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.manageUser", "page": "launcher", "section": "Preferred applications", "title": "User account settings", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.networkEthernet", "page": "launcher", "section": "Preferred applications", "title": "Ethernet settings", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.taskManager", "page": "launcher", "section": "Preferred applications", "title": "Task manager", "kind": "text", "description": "vminfo opens in your preferred terminal. Other commands run as entered."},
    {"path": "apps.terminal", "page": "launcher", "section": "Preferred applications", "title": "Terminal", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.update", "page": "launcher", "section": "Preferred applications", "title": "Software updates", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "apps.volumeMixer", "page": "launcher", "section": "Preferred applications", "title": "Volume mixer", "kind": "text", "description": "Command used by this shell action. Saved without running it."},
    {"path": "background.widgets.clock.enable", "page": "widgets", "section": "Desktop clock", "title": "Show desktop clock", "kind": "toggle", "description": "Display a clock on the wallpaper."},
    {"path": "background.widgets.clock.showOnlyWhenLocked", "page": "widgets", "section": "Desktop clock", "title": "Show only when locked", "kind": "toggle"},
    {"path": "background.widgets.clock.placementStrategy", "page": "widgets", "section": "Desktop clock", "title": "Clock placement", "kind": "choice", "description": "Free uses saved coordinates. Automatic placement follows window occupancy.", "choices": [{"value": "free", "label": "Free position"}, {"value": "leastBusy", "label": "Least occupied workspace area"}, {"value": "mostBusy", "label": "Most occupied workspace area"}]},
    {"path": "background.widgets.clock.x", "page": "widgets", "section": "Desktop clock", "title": "Horizontal position", "kind": "number", "suffix": "px", "min": -10000, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true], ["background.widgets.clock.placementStrategy", "free"]]},
    {"path": "background.widgets.clock.y", "page": "widgets", "section": "Desktop clock", "title": "Vertical position", "kind": "number", "suffix": "px", "min": -10000, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true], ["background.widgets.clock.placementStrategy", "free"]]},
    {"path": "background.widgets.clock.style", "page": "widgets", "section": "Desktop clock", "title": "Clock style", "kind": "choice", "choices": [{"value": "cookie", "label": "Analog"}, {"value": "digital", "label": "Digital"}]},
    {"path": "background.widgets.clock.styleLocked", "page": "widgets", "section": "Desktop clock", "title": "Lock-screen clock style", "kind": "choice", "choices": [{"value": "cookie", "label": "Analog"}, {"value": "digital", "label": "Digital"}]},
    {"path": "background.widgets.clock.cookie.aiStyling", "page": "widgets", "section": "Analog clock details", "title": "Style clock with the sidebar assistant", "kind": "toggle", "description": "Sends a reduced wallpaper image to the configured assistant service."},
    {"path": "background.widgets.clock.cookie.sides", "page": "widgets", "section": "Analog clock details", "title": "Clock shape sides", "kind": "number", "min": 0.0, "max": 40.0, "step": 1, "scale": 1},
    {"path": "background.widgets.clock.cookie.dialNumberStyle", "page": "widgets", "section": "Analog clock details", "title": "Dial number style", "kind": "choice", "choices": [{"value": "dots", "label": "Dots"}, {"value": "numbers", "label": "Numbers"}, {"value": "full", "label": "Full"}, {"value": "none", "label": "None"}]},
    {"path": "background.widgets.clock.cookie.hourHandStyle", "page": "widgets", "section": "Analog clock details", "title": "Hour hand style", "kind": "choice", "choices": [{"value": "classic", "label": "Classic"}, {"value": "fill", "label": "Fill"}, {"value": "hollow", "label": "Hollow"}, {"value": "hide", "label": "Hide"}]},
    {"path": "background.widgets.clock.cookie.minuteHandStyle", "page": "widgets", "section": "Analog clock details", "title": "Minute hand style", "kind": "choice", "choices": [{"value": "classic", "label": "Classic"}, {"value": "thin", "label": "Thin"}, {"value": "medium", "label": "Medium"}, {"value": "bold", "label": "Bold"}, {"value": "hide", "label": "Hide"}]},
    {"path": "background.widgets.clock.cookie.secondHandStyle", "page": "widgets", "section": "Analog clock details", "title": "Second hand style", "kind": "choice", "choices": [{"value": "dot", "label": "Dot"}, {"value": "line", "label": "Line"}, {"value": "classic", "label": "Classic"}, {"value": "hide", "label": "Hide"}]},
    {"path": "background.widgets.clock.cookie.dateStyle", "page": "widgets", "section": "Analog clock details", "title": "Date style", "kind": "choice", "choices": [{"value": "border", "label": "Border"}, {"value": "rect", "label": "Rect"}, {"value": "bubble", "label": "Bubble"}, {"value": "hide", "label": "Hide"}]},
    {"path": "background.widgets.clock.cookie.timeIndicators", "page": "widgets", "section": "Analog clock details", "title": "Time indicators", "kind": "toggle"},
    {"path": "background.widgets.clock.cookie.hourMarks", "page": "widgets", "section": "Analog clock details", "title": "Hour marks", "kind": "toggle"},
    {"path": "background.widgets.clock.cookie.dateInClock", "page": "widgets", "section": "Analog clock details", "title": "Date in clock", "kind": "toggle"},
    {"path": "background.widgets.clock.cookie.constantlyRotate", "page": "widgets", "section": "Analog clock details", "title": "Continuously rotate analog clock", "kind": "toggle", "description": "Uses continuous rendering and can increase GPU usage."},
    {"path": "background.widgets.clock.cookie.useSineCookie", "page": "widgets", "section": "Analog clock details", "title": "Use old sine wave cookie implementation", "kind": "toggle"},
    {"path": "background.widgets.clock.digital.adaptiveAlignment", "page": "widgets", "section": "Digital clock details", "title": "Adaptive alignment", "kind": "toggle", "when": [["background.widgets.clock.enable", true]]},
    {"path": "background.widgets.clock.digital.showDate", "page": "widgets", "section": "Digital clock details", "title": "Show date", "kind": "toggle", "when": [["background.widgets.clock.enable", true]]},
    {"path": "background.widgets.clock.digital.animateChange", "page": "widgets", "section": "Digital clock details", "title": "Animate clock changes", "kind": "toggle", "when": [["background.widgets.clock.enable", true]]},
    {"path": "background.widgets.clock.digital.vertical", "page": "widgets", "section": "Digital clock details", "title": "Stack digital clock vertically", "kind": "toggle", "when": [["background.widgets.clock.enable", true]]},
    {"path": "background.widgets.clock.digital.font.family", "page": "widgets", "section": "Digital clock details", "title": "Clock typeface", "kind": "text", "description": "Separate from the general shell font profile.", "when": [["background.widgets.clock.enable", true]]},
    {"path": "background.widgets.clock.digital.font.weight", "page": "widgets", "section": "Digital clock details", "title": "Clock font weight", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true]], "description": "Variable-font weight axis, when supported by the selected font."},
    {"path": "background.widgets.clock.digital.font.width", "page": "widgets", "section": "Digital clock details", "title": "Clock font width", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true]], "description": "Variable-font width axis, when supported by the selected font."},
    {"path": "background.widgets.clock.digital.font.size", "page": "widgets", "section": "Digital clock details", "title": "Clock font size", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true]], "description": "Size of the large digital wallpaper clock."},
    {"path": "background.widgets.clock.digital.font.roundness", "page": "widgets", "section": "Digital clock details", "title": "Clock font roundness", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.clock.enable", true]], "description": "Variable-font roundness axis, when supported by the selected font."},
    {"path": "background.widgets.clock.quote.enable", "page": "widgets", "section": "Clock quote", "title": "Show clock quote", "kind": "toggle"},
    {"path": "background.widgets.clock.quote.text", "page": "widgets", "section": "Clock quote", "title": "Clock quote text", "kind": "text"},
    {"path": "background.widgets.weather.enable", "keywords": "poll polling weather refresh", "page": "widgets", "section": "Desktop weather", "title": "Show desktop weather", "kind": "toggle", "description": "Display the shared weather service on the wallpaper."},
    {"path": "background.widgets.weather.placementStrategy", "page": "widgets", "section": "Desktop weather", "title": "Weather placement", "kind": "choice", "description": "Free uses saved coordinates. Automatic placement follows window occupancy.", "choices": [{"value": "free", "label": "Free position"}, {"value": "leastBusy", "label": "Least occupied workspace area"}, {"value": "mostBusy", "label": "Most occupied workspace area"}]},
    {"path": "background.widgets.weather.x", "page": "widgets", "section": "Desktop weather", "title": "Horizontal position", "kind": "number", "suffix": "px", "min": -10000, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.weather.enable", true], ["background.widgets.weather.placementStrategy", "free"]]},
    {"path": "background.widgets.weather.y", "page": "widgets", "section": "Desktop weather", "title": "Vertical position", "kind": "number", "suffix": "px", "min": -10000, "max": 10000, "step": 1, "scale": 1, "when": [["background.widgets.weather.enable", true], ["background.widgets.weather.placementStrategy", "free"]]},
    {"path": "background.discovery.theme", "page": "wallpaper", "section": "Wallpaper discovery", "title": "Discovery mood", "kind": "choice", "description": "The source mix used by Discover and automatic rotation.", "choices": [{"value": "mix", "label": "Mix"}, {"value": "mario", "label": "Mario"}, {"value": "lis", "label": "Lis"}, {"value": "tomb", "label": "Tomb"}, {"value": "painted", "label": "Painted"}, {"value": "worlds", "label": "Worlds"}]},
    {"path": "background.discovery.includeKonachan", "page": "wallpaper", "section": "Wallpaper discovery", "title": "Include Konachan anime in the mix", "kind": "toggle"},
    {"path": "background.discovery.rotate", "keywords": "timing timer repeat periodic rotation", "page": "wallpaper", "section": "Wallpaper discovery", "title": "Rotate wallpapers automatically", "kind": "toggle", "description": "Starts wallpaper downloads at the selected interval."},
    {"path": "background.discovery.intervalMinutes", "page": "wallpaper", "section": "Wallpaper discovery", "title": "Wallpaper rotation interval", "kind": "number", "description": "Automatic discovery uses at least 15 minutes between wallpapers.", "min": 15, "max": 1440, "step": 15, "scale": 1, "unit": "min"},
    {"path": "background.discovery.prefetchCount", "page": "wallpaper", "section": "Offline & preview queue", "title": "Prefetch batch size", "kind": "number", "description": "Download this many originals for preview without changing the wallpaper or colors.", "min": 1, "max": 24, "step": 1, "scale": 1},
    {"path": "background.discovery.prefetchAhead", "page": "wallpaper", "section": "Offline & preview queue", "title": "Keep the offline queue filled", "kind": "toggle", "description": "While automatic rotation is enabled, refill the queue in the background when fewer than two images remain. Rotation uses these saved originals first."},
    {"path": "background.discovery.storageLimitMiB", "page": "wallpaper", "section": "Saved wallpaper storage", "title": "Wallpaper storage limit", "kind": "number", "suffix": "MiB", "description": "Oldest unkept downloads are removed when space is needed. Current and kept wallpapers are protected; new downloads pause if they fill the limit.", "min": 64, "max": 32768, "step": 64, "scale": 1},
    {"path": "background.discovery.minFreeMiB", "page": "wallpaper", "section": "Saved wallpaper storage", "title": "Keep disk space free", "kind": "number", "suffix": "MiB", "description": "Pause downloads before free disk space falls below this reserve.", "min": 0, "max": 32768, "step": 256, "scale": 1},
    {"path": "background.hideWhenFullscreen", "page": "design", "section": "Wallpaper visibility", "title": "Hide background under fullscreen apps", "kind": "toggle", "description": "Reduces unnecessary background rendering."},
    {"path": "background.parallax.vertical", "page": "design", "section": "Wallpaper motion", "title": "Vertical wallpaper parallax", "kind": "toggle"},
    {"path": "background.parallax.autoVertical", "page": "design", "section": "Wallpaper motion", "title": "Automatic vertical parallax", "kind": "toggle"},
    {"path": "background.parallax.enableWorkspace", "page": "design", "section": "Wallpaper motion", "title": "Follow workspace changes", "kind": "toggle"},
    {"path": "background.parallax.workspaceZoom", "page": "design", "section": "Wallpaper motion", "title": "Preferred wallpaper zoom", "kind": "number", "min": 0, "max": 300, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "background.parallax.enableSidebar", "page": "design", "section": "Wallpaper motion", "title": "Depends on sidebars", "kind": "toggle"},
    {"path": "background.parallax.widgetsFactor", "page": "design", "section": "Wallpaper motion", "title": "Widget parallax strength", "kind": "number", "min": 0, "max": 300, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "bar.autoHide.enable", "page": "bar", "section": "Auto-hide", "title": "Hide bar automatically", "kind": "toggle", "description": "Reveal the bar from its edge or the Super key, as configured below."},
    {"path": "bar.autoHide.hoverRegionWidth", "page": "bar", "section": "Auto-hide", "title": "Hover region width", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "bar.autoHide.pushWindows", "page": "bar", "section": "Auto-hide", "title": "Push windows", "kind": "toggle"},
    {"path": "bar.autoHide.showWhenPressingSuper.enable", "page": "bar", "section": "Auto-hide", "title": "Show the bar while holding Super", "kind": "toggle"},
    {"path": "bar.autoHide.showWhenPressingSuper.delay", "page": "bar", "section": "Auto-hide", "title": "Bar reveal delay", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "ms", "description": "How long to hold Super before the hidden bar appears."},
    {"path": "bar.bottom", "page": "bar", "section": "Bar layout", "title": "Place horizontal bar at bottom", "kind": "toggle", "description": "Disable to place it at the top. Vertical layout has its own orientation."},
    {"path": "bar.cornerStyle", "page": "bar", "section": "Bar layout", "title": "Corner style", "kind": "choice", "min": 0, "max": 10000, "step": 1, "scale": 1, "choices": [{"value": 0, "label": "Hug screen"}, {"value": 1, "label": "Floating"}, {"value": 2, "label": "Rectangle"}]},
    {"path": "bar.floatStyleShadow", "page": "bar", "section": "Bar layout", "title": "Float style shadow", "kind": "toggle"},
    {"path": "bar.borderless", "page": "bar", "section": "Bar layout", "title": "Borderless", "kind": "toggle"},
    {"path": "bar.topLeftIcon", "page": "bar", "section": "Bar layout", "title": "Top left icon", "kind": "text"},
    {"path": "bar.showBackground", "page": "bar", "section": "Bar layout", "title": "Show background", "kind": "toggle"},
    {"path": "bar.verbose", "page": "bar", "section": "Bar layout", "title": "Verbose", "kind": "toggle"},
    {"path": "bar.vertical", "page": "bar", "section": "Bar layout", "title": "Use a vertical bar", "kind": "toggle", "description": "Switch between horizontal and vertical layout."},
    {"path": "bar.resources.alwaysShowSwap", "page": "bar", "section": "Resource warnings", "title": "Always show swap usage", "kind": "toggle", "description": "Otherwise the indicator follows its normal visibility rules."},
    {"path": "bar.resources.alwaysShowCpu", "page": "bar", "section": "Resource warnings", "title": "Always show CPU usage", "kind": "toggle", "description": "Otherwise the indicator follows its normal visibility rules."},
    {"path": "bar.resources.memoryWarningThreshold", "page": "bar", "section": "Resource warnings", "title": "Memory warning threshold", "kind": "number", "min": 0, "max": 101, "step": 1, "scale": 1, "suffix": "%", "description": "Highlight when used RAM reaches this percentage. Reclaimable memory is counted as available."},
    {"path": "bar.resources.swapWarningThreshold", "page": "bar", "section": "Resource warnings", "title": "Swap warning threshold", "kind": "number", "min": 0, "max": 101, "step": 1, "scale": 1, "suffix": "%", "description": "Highlight when used swap reaches this percentage across all swap devices. This is a usage cue, not a memory-pressure measurement."},
    {"path": "bar.resources.cpuWarningThreshold", "page": "bar", "section": "Resource warnings", "title": "CPU usage warning", "kind": "number", "min": 0, "max": 101, "step": 1, "scale": 1, "suffix": "%", "description": "Highlight when total CPU utilization reaches this percentage across all logical CPUs."},
    {"path": "bar.screenList", "page": "bar", "section": "Bar layout", "title": "Show bar on these outputs", "kind": "lines", "description": "One output name per line. Empty uses every connected output."},
    {"path": "bar.utilButtons.showScreenSnip", "page": "bar", "section": "Utility buttons", "title": "Screen snip", "kind": "toggle"},
    {"path": "bar.utilButtons.showColorPicker", "page": "bar", "section": "Utility buttons", "title": "Color picker", "kind": "toggle"},
    {"path": "bar.utilButtons.showMicToggle", "page": "bar", "section": "Utility buttons", "title": "Mic toggle", "kind": "toggle"},
    {"path": "bar.utilButtons.showKeyboardToggle", "page": "bar", "section": "Utility buttons", "title": "Keyboard toggle", "kind": "toggle"},
    {"path": "bar.utilButtons.showDarkModeToggle", "page": "bar", "section": "Utility buttons", "title": "Dark/Light toggle", "kind": "toggle"},
    {"path": "bar.utilButtons.showPerformanceProfileToggle", "page": "bar", "section": "Utility buttons", "title": "Performance profile toggle", "kind": "toggle"},
    {"path": "bar.utilButtons.showScreenRecord", "page": "bar", "section": "Utility buttons", "title": "Record", "kind": "toggle"},
    {"path": "bar.workspaces.monochromeIcons", "page": "bar", "section": "Workspace indicators", "title": "Monochrome icons", "kind": "toggle"},
    {"path": "bar.workspaces.shown", "page": "bar", "section": "Workspace indicators", "title": "Workspace slots", "kind": "number", "description": "Number of workspace indicators in each group.", "min": 1, "max": 30, "step": 1, "scale": 1},
    {"path": "bar.workspaces.showAppIcons", "page": "bar", "section": "Workspace indicators", "title": "Show app icons", "kind": "toggle"},
    {"path": "bar.workspaces.alwaysShowNumbers", "page": "bar", "section": "Workspace indicators", "title": "Always show numbers", "kind": "toggle"},
    {"path": "bar.workspaces.numberMap", "page": "bar", "section": "Workspace indicators", "title": "Custom workspace labels", "kind": "lines", "description": "One label per line, in workspace order."},
    {"path": "bar.workspaces.useNerdFont", "page": "bar", "section": "Workspace indicators", "title": "Use Nerd Font", "kind": "toggle"},
    {"path": "bar.weather.enable", "keywords": "poll polling weather refresh", "page": "bar", "section": "Bar weather", "title": "Show weather in bar", "kind": "toggle", "description": "Uses the shared weather location and units."},
    {"path": "bar.weather.enableGPS", "page": "bar", "section": "Bar weather", "title": "Locate weather automatically", "kind": "toggle", "description": "Disable to use the city entered below."},
    {"path": "bar.weather.city", "page": "bar", "section": "Bar weather", "title": "Weather city", "kind": "text", "description": "Used when automatic location is off.", "when": [["bar.weather.enableGPS", false]]},
    {"path": "bar.weather.useUSCS", "page": "bar", "section": "Bar weather", "title": "Use fahrenheit and US units", "kind": "toggle", "description": "Applies to the shared weather service."},
    {"path": "bar.weather.fetchInterval", "page": "bar", "section": "Bar weather", "title": "Weather refresh interval", "kind": "number", "min": 5.0, "max": 50.0, "step": 1, "scale": 1, "unit": "min", "description": "Time between network weather requests. 15 minutes keeps the weather useful without polling every few minutes."},
    {"path": "bar.indicators.notifications.showUnreadCount", "page": "notifications", "section": "On-screen feedback", "title": "Unread indicator: show count", "kind": "toggle"},
    {"path": "bar.tooltips.clickToShow", "page": "bar", "section": "Bar tooltips", "title": "Click to show", "kind": "toggle"},
    {"path": "battery.low", "page": "session", "section": "Battery warnings & suspend", "title": "Low battery warning threshold", "kind": "number", "suffix": "%", "min": 0, "max": 101, "step": 1, "scale": 1},
    {"path": "battery.critical", "page": "session", "section": "Battery warnings & suspend", "title": "Critical battery warning threshold", "kind": "number", "suffix": "%", "min": 0, "max": 101, "step": 1, "scale": 1},
    {"path": "battery.full", "page": "session", "section": "Battery warnings & suspend", "title": "Full battery warning threshold", "kind": "number", "suffix": "%", "min": 0, "max": 101, "step": 1, "scale": 1, "description": "101 disables the full-charge warning."},
    {"path": "battery.automaticSuspend", "page": "session", "section": "Battery warnings & suspend", "title": "Automatic suspend", "kind": "toggle"},
    {"path": "battery.suspend", "page": "session", "section": "Battery warnings & suspend", "title": "Automatic suspend threshold", "kind": "number", "suffix": "%", "min": 0, "max": 101, "step": 1, "scale": 1},
    {"path": "calendar.locale", "page": "general", "section": "Time & date", "title": "Locale", "kind": "text"},
    {"path": "cheatsheet.superKey", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Super key", "kind": "text"},
    {"path": "cheatsheet.useMacSymbol", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Use macOS-like symbols for mods keys", "kind": "toggle"},
    {"path": "cheatsheet.splitButtons", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Split buttons", "kind": "toggle"},
    {"path": "cheatsheet.useMouseSymbol", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Use symbols for mouse", "kind": "toggle"},
    {"path": "cheatsheet.useFnSymbol", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Use symbols for function keys", "kind": "toggle"},
    {"path": "cheatsheet.fontSize.key", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Keybind font size", "kind": "number", "min": 8.0, "max": 30.0, "step": 1, "scale": 1},
    {"path": "cheatsheet.fontSize.comment", "page": "advanced", "section": "Keyboard shortcut sheet", "title": "Description font size", "kind": "number", "min": 8.0, "max": 30.0, "step": 1, "scale": 1},
    {"path": "conflictKiller.autoKillNotificationDaemons", "page": "advanced", "section": "Conflicting desktop services", "title": "Stop other notification daemons", "kind": "toggle", "description": "Allows the shell conflict service to stop competing notification providers."},
    {"path": "conflictKiller.autoKillTrays", "page": "advanced", "section": "Conflicting desktop services", "title": "Stop other tray services", "kind": "toggle", "description": "Allows the shell conflict service to stop competing system trays."},
    {"path": "crosshair.code", "page": "capture", "section": "Floating overlays", "title": "Crosshair code", "kind": "text"},
    {"path": "dock.enable", "page": "workspaces", "section": "Application dock", "title": "Show application dock", "kind": "toggle", "description": "Enable the dock on the desktop."},
    {"path": "dock.monochromeIcons", "page": "workspaces", "section": "Application dock", "title": "Tint app icons", "kind": "toggle"},
    {"path": "dock.height", "page": "workspaces", "section": "Application dock", "title": "Height", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "dock.hoverRegionHeight", "page": "workspaces", "section": "Application dock", "title": "Hover region height", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "dock.pinnedOnStartup", "page": "workspaces", "section": "Application dock", "title": "Pinned on startup", "kind": "toggle"},
    {"path": "dock.hoverToReveal", "page": "workspaces", "section": "Application dock", "title": "Hover to reveal", "kind": "toggle"},
    {"path": "dock.pinnedApps", "page": "workspaces", "section": "Application dock", "title": "Pinned dock applications", "kind": "lines", "description": "One desktop application ID per line, in display order."},
    {"path": "dock.ignoredAppRegexes", "page": "workspaces", "section": "Application dock", "title": "Ignored app regexes", "kind": "lines"},
    {"path": "interactions.scrolling.fasterTouchpadScroll", "page": "advanced", "section": "Scrolling & edge input", "title": "Faster touchpad scroll", "kind": "toggle"},
    {"path": "interactions.scrolling.mouseScrollDeltaThreshold", "page": "advanced", "section": "Scrolling & edge input", "title": "Mouse wheel step threshold", "kind": "number", "min": 1, "max": 1200, "step": 1, "scale": 1, "suffix": "units", "description": "Wheel angle-delta units used to distinguish a mouse notch from touchpad scrolling. A standard notch is 120 units."},
    {"path": "interactions.scrolling.mouseScrollFactor", "page": "advanced", "section": "Scrolling & edge input", "title": "Mouse scroll factor", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "interactions.scrolling.touchpadScrollFactor", "page": "advanced", "section": "Scrolling & edge input", "title": "Touchpad scroll factor", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "interactions.deadPixelWorkaround.enable", "page": "advanced", "section": "Scrolling & edge input", "title": "Enable the dead-pixel workaround", "kind": "toggle"},
    {"path": "language.ui", "page": "general", "section": "Language", "title": "Interface language", "kind": "text", "description": "Use auto for your system locale, or a translation code such as en_US or pt_BR."},
    {"path": "language.translator.targetLanguage", "page": "services", "section": "Translator", "title": "Target language", "kind": "text"},
    {"path": "language.translator.sourceLanguage", "page": "services", "section": "Translator", "title": "Source language", "kind": "text"},
    {"path": "launcher.pinnedApps", "page": "launcher", "section": "Launcher search", "title": "Pinned launcher applications", "kind": "lines", "description": "One desktop application ID per line."},
    {"path": "light.night.automatic", "page": "audio", "section": "Night light", "title": "Schedule night light", "kind": "toggle", "description": "Use the start and end times below."},
    {"path": "light.night.from", "page": "audio", "section": "Night light", "title": "Night light starts", "kind": "text", "description": "24-hour time, HH:mm."},
    {"path": "light.night.to", "page": "audio", "section": "Night light", "title": "Night light ends", "kind": "text", "description": "24-hour time, HH:mm."},
    {"path": "light.night.colorTemperature", "page": "audio", "section": "Night light", "title": "Night-light temperature (k)", "kind": "number", "description": "Lower values are warmer.", "min": 1000, "max": 10000, "step": 100, "scale": 1},
    {"path": "light.antiFlashbang.enable", "page": "audio", "section": "Night light", "title": "Dim bright windows", "kind": "toggle", "description": "Applies the shell anti-flashbang behavior."},
    {"path": "lock.useHyprlock", "page": "session", "section": "Lock screen", "title": "Use Hyprlock", "kind": "toggle", "description": "Use the external locker instead of the shell lock screen."},
    {"path": "lock.launchOnStartup", "page": "session", "section": "Lock screen", "title": "Lock when the shell starts", "kind": "toggle", "description": "Applies on the next shell start."},
    {"path": "lock.blur.enable", "page": "session", "section": "Lock screen", "title": "Blur the lock screen", "kind": "toggle"},
    {"path": "lock.blur.radius", "page": "session", "section": "Lock screen", "title": "Lock screen blur radius", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "lock.blur.extraZoom", "page": "session", "section": "Lock screen", "title": "Extra wallpaper zoom", "kind": "number", "min": 0, "max": 300, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "lock.centerClock", "page": "session", "section": "Lock screen", "title": "Center clock", "kind": "toggle"},
    {"path": "lock.showLockedText", "page": "session", "section": "Lock screen", "title": "Show locked text", "kind": "toggle"},
    {"path": "lock.security.unlockKeyring", "page": "session", "section": "Lock screen", "title": "Unlock the keyring", "kind": "toggle", "description": "Unlock stored secrets after authenticating in the shell locker."},
    {"path": "lock.security.requirePasswordToPower", "page": "session", "section": "Lock screen", "title": "Require authentication for power actions", "kind": "toggle", "description": "Applies to power controls in the shell lock screen."},
    {"path": "lock.materialShapeChars", "page": "session", "section": "Lock screen", "title": "Material shape chars", "kind": "toggle"},
    {"path": "media.filterDuplicatePlayers", "page": "audio", "section": "Media players", "title": "Filter duplicate players", "kind": "toggle"},
    {"path": "networking.userAgent", "page": "advanced", "section": "Other preferences", "title": "Service user agent", "kind": "text", "description": "Header sent by services that require a browser-like user agent."},
    {"path": "notifications.timeout", "page": "notifications", "section": "Notification popups", "title": "Notification popup duration", "kind": "number", "description": "Used when the application does not provide its own timeout.", "min": 1000.0, "max": 60000.0, "step": 1, "scale": 1, "unit": "ms"},
    {"path": "notifications.monitor.enable", "page": "notifications", "section": "Notification popups", "title": "Use one notification output", "kind": "toggle", "description": "Choose a connected output below. Otherwise popups can appear on all outputs."},
    {"path": "notifications.monitor.name", "page": "notifications", "section": "Notification popups", "title": "Notification output", "kind": "monitor", "description": "Use the output name shown by your display, for example DP-1.", "when": [["notifications.monitor.enable", true]]},
    {"path": "osd.timeout", "page": "notifications", "section": "On-screen feedback", "title": "Volume and brightness overlay duration", "kind": "number", "description": "How long on-screen feedback remains visible.", "min": 100.0, "max": 3000.0, "step": 1, "scale": 1, "unit": "ms"},
    {"path": "osk.layout", "page": "control", "section": "On-screen keyboard", "title": "Current keyboard layout", "kind": "info", "description": "Follows the active Hyprland keyboard layout."},
    {"path": "osk.pinnedOnStartup", "page": "control", "section": "On-screen keyboard", "title": "Pinned on startup", "kind": "toggle"},
    {"path": "overlay.openingZoomAnimation", "page": "capture", "section": "Floating overlays", "title": "Enable opening zoom animation", "kind": "toggle"},
    {"path": "overlay.darkenScreen", "page": "capture", "section": "Floating overlays", "title": "Darken screen", "kind": "toggle"},
    {"path": "overlay.clickthroughOpacity", "page": "capture", "section": "Floating overlays", "title": "Clickthrough opacity", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "overlay.floatingImage.imageSource", "page": "capture", "section": "Floating overlays", "title": "Image source", "kind": "longtext"},
    {"path": "overlay.floatingImage.scale", "page": "capture", "section": "Floating overlays", "title": "Floating image scale", "kind": "number", "min": 0, "max": 300, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "overview.enable", "page": "workspaces", "section": "Workspace overview", "title": "Enable workspace overview", "kind": "toggle", "description": "Shows the workspace grid when you open the overview."},
    {"path": "overview.scale", "page": "workspaces", "section": "Workspace overview", "title": "Scale", "kind": "number", "min": 0, "max": 300, "step": 1, "scale": 100, "suffix": "%"},
    {"path": "overview.rows", "page": "workspaces", "section": "Workspace overview", "title": "Overview rows", "kind": "number", "min": 1, "max": 20, "step": 1, "scale": 1},
    {"path": "overview.columns", "page": "workspaces", "section": "Workspace overview", "title": "Overview columns", "kind": "number", "min": 1, "max": 20, "step": 1, "scale": 1},
    {"path": "overview.orderRightLeft", "page": "workspaces", "section": "Workspace overview", "title": "Arrange workspaces right to left", "kind": "toggle"},
    {"path": "overview.orderBottomUp", "page": "workspaces", "section": "Workspace overview", "title": "Arrange workspaces bottom to top", "kind": "toggle"},
    {"path": "overview.centerIcons", "page": "workspaces", "section": "Workspace overview", "title": "Center icons", "kind": "toggle"},
    {"path": "regionSelector.targetRegions.windows", "page": "capture", "section": "Screenshot selection", "title": "Snap to windows", "kind": "toggle", "description": "Offer window boundaries as screenshot targets."},
    {"path": "regionSelector.targetRegions.layers", "page": "capture", "section": "Screenshot selection", "title": "Snap to shell surfaces", "kind": "toggle", "description": "Offer panels and other desktop layers as screenshot targets."},
    {"path": "regionSelector.targetRegions.content", "page": "capture", "section": "Screenshot selection", "title": "Detect image regions", "kind": "toggle", "description": "Find contained areas using local image processing."},
    {"path": "regionSelector.targetRegions.showLabel", "page": "capture", "section": "Screenshot selection", "title": "Label detected regions", "kind": "toggle", "description": "Show the target label beside each region."},
    {"path": "regionSelector.targetRegions.opacity", "page": "capture", "section": "Screenshot selection", "title": "Target highlight opacity", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "description": "Strength of window and layer target highlights."},
    {"path": "regionSelector.targetRegions.contentRegionOpacity", "page": "capture", "section": "Screenshot selection", "title": "Image-region highlight opacity", "kind": "number", "min": 0, "max": 100, "step": 1, "scale": 100, "suffix": "%", "description": "Strength of automatically detected image regions."},
    {"path": "regionSelector.targetRegions.selectionPadding", "page": "capture", "section": "Screenshot selection", "title": "Selection padding", "kind": "number", "suffix": "px", "min": 0, "max": 10000, "step": 1, "scale": 1, "description": "Padding around a detected region."},
    {"path": "regionSelector.rect.showAimLines", "page": "capture", "section": "Screenshot selection", "title": "Show aim lines", "kind": "toggle"},
    {"path": "regionSelector.circle.strokeWidth", "page": "capture", "section": "Screenshot selection", "title": "Stroke width", "kind": "number", "min": 1.0, "max": 20.0, "step": 1, "scale": 1},
    {"path": "regionSelector.circle.padding", "page": "capture", "section": "Screenshot selection", "title": "Padding", "kind": "number", "min": 0.0, "max": 100.0, "step": 1, "scale": 1},
    {"path": "regionSelector.annotation.useSatty", "page": "capture", "section": "Screenshot selection", "title": "Use Satty for annotations", "kind": "toggle", "description": "Requires Satty to be installed; otherwise use the default editor."},
    {"path": "resources.updateInterval", "page": "bar", "section": "Resource monitoring", "title": "Resource sampling interval", "kind": "number", "description": "Refresh CPU, memory, swap, GPU and pressure readings. 1000 ms suits a responsive desktop; the minimum is 250 ms.", "min": 250, "max": 60000, "step": 250, "scale": 1, "unit": "ms"},
    {"path": "resources.historyLength", "page": "bar", "section": "Resource monitoring", "title": "Resource history samples", "kind": "number", "description": "Samples retained per resource graph. 60 samples at 1000 ms cover about one minute.", "min": 2, "max": 600, "step": 1, "scale": 1, "suffix": "samples"},
    {"path": "tray.monochromeIcons", "page": "bar", "section": "System tray", "title": "Monochrome icons", "kind": "toggle"},
    {"path": "tray.showItemId", "page": "bar", "section": "System tray", "title": "Show tray item IDs", "kind": "toggle"},
    {"path": "tray.invertPinnedItems", "page": "bar", "section": "System tray", "title": "Invert pinned items", "kind": "toggle"},
    {"path": "tray.pinnedItems", "page": "bar", "section": "System tray", "title": "Pinned items", "kind": "lines"},
    {"path": "tray.filterPassive", "page": "bar", "section": "System tray", "title": "Hide passive tray items", "kind": "toggle"},
    {"path": "musicRecognition.timeout", "page": "audio", "section": "Music recognition", "title": "Music recognition timeout", "kind": "number", "min": 10.0, "max": 100.0, "step": 1, "scale": 1, "unit": "s"},
    {"path": "musicRecognition.interval", "page": "audio", "section": "Music recognition", "title": "Music recognition check interval", "kind": "number", "min": 2.0, "max": 10.0, "step": 1, "scale": 1, "unit": "s"},
    {"path": "search.nonAppResultDelay", "page": "launcher", "section": "Launcher search", "title": "Non-app search delay", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "ms", "description": "Wait after typing before loading non-app search results."},
    {"path": "search.engineBaseUrl", "page": "launcher", "section": "Launcher search", "title": "Web search URL", "kind": "text"},
    {"path": "search.excludedSites", "page": "launcher", "section": "Launcher search", "title": "Excluded search sites", "kind": "lines"},
    {"path": "search.sloppy", "page": "launcher", "section": "Launcher search", "title": "Use edit-distance matching", "kind": "toggle", "description": "Use Levenshtein distance for approximate matches in launcher searches."},
    {"path": "search.prefix.showDefaultActionsWithoutPrefix", "page": "launcher", "section": "Search prefixes", "title": "Show default actions without prefix", "kind": "toggle"},
    {"path": "search.prefix.action", "page": "launcher", "section": "Search prefixes", "title": "Action prefix", "kind": "text"},
    {"path": "search.prefix.app", "page": "launcher", "section": "Search prefixes", "title": "Application prefix", "kind": "text", "description": "Character used to restrict launcher results to applications."},
    {"path": "search.prefix.clipboard", "page": "launcher", "section": "Search prefixes", "title": "Clipboard prefix", "kind": "text"},
    {"path": "search.prefix.emojis", "page": "launcher", "section": "Search prefixes", "title": "Emoji prefix", "kind": "text"},
    {"path": "search.prefix.math", "page": "launcher", "section": "Search prefixes", "title": "Calculator prefix", "kind": "text"},
    {"path": "search.prefix.shellCommand", "page": "launcher", "section": "Search prefixes", "title": "Shell command prefix", "kind": "text"},
    {"path": "search.prefix.webSearch", "page": "launcher", "section": "Search prefixes", "title": "Web search prefix", "kind": "text"},
    {"path": "search.imageSearch.imageSearchEngineBaseUrl", "page": "capture", "section": "Save & search images", "title": "Image search URL", "kind": "text"},
    {"path": "search.imageSearch.useCircleSelection", "page": "capture", "section": "Save & search images", "title": "Use circle selection", "kind": "toggle"},
    {"path": "sidebar.keepRightSidebarLoaded", "page": "control", "section": "Panel loading", "title": "Keep control center ready", "kind": "toggle", "description": "Keeps its content loaded while closed, trading memory for faster opening."},
    {"path": "sidebar.translator.enable", "page": "services", "section": "Translator", "title": "Show translator in left sidebar", "kind": "toggle", "description": "Translation uses the language settings below."},
    {"path": "sidebar.translator.delay", "page": "services", "section": "Translator", "title": "Translation typing delay", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "description": "Wait after typing before sending a translation request.", "unit": "ms"},
    {"path": "sidebar.ai.textFadeIn", "page": "services", "section": "Sidebar assistant", "title": "Text fade in", "kind": "toggle"},
    {"path": "sidebar.booru.limit", "page": "services", "section": "Image providers", "title": "Image result limit", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "sidebar.booru.zerochan.username", "page": "services", "section": "Image providers", "title": "Zerochan username", "kind": "text"},
    {"path": "sidebar.cornerOpen.enable", "page": "control", "section": "Corner gestures", "title": "Open sidebars from screen corners", "kind": "toggle", "description": "Uses the edge regions configured below."},
    {"path": "sidebar.cornerOpen.bottom", "page": "control", "section": "Corner gestures", "title": "Place at bottom", "kind": "toggle"},
    {"path": "sidebar.cornerOpen.valueScroll", "page": "control", "section": "Corner gestures", "title": "Value scroll", "kind": "toggle"},
    {"path": "sidebar.cornerOpen.clickless", "page": "control", "section": "Corner gestures", "title": "Hover to trigger", "kind": "toggle"},
    {"path": "sidebar.cornerOpen.cornerRegionWidth", "page": "control", "section": "Corner gestures", "title": "Region width", "kind": "number", "min": 1.0, "max": 300.0, "step": 1, "scale": 1},
    {"path": "sidebar.cornerOpen.cornerRegionHeight", "page": "control", "section": "Corner gestures", "title": "Corner region height", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "sidebar.cornerOpen.visualize", "page": "control", "section": "Corner gestures", "title": "Visualize region", "kind": "toggle"},
    {"path": "sidebar.cornerOpen.clicklessCornerEnd", "page": "control", "section": "Corner gestures", "title": "Force hover open at absolute corner", "kind": "toggle"},
    {"path": "sidebar.cornerOpen.clicklessCornerVerticalOffset", "page": "control", "section": "Corner gestures", "title": "Clickless corner vertical offset", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "sidebar.quickToggles.style", "page": "control", "section": "Quick tiles", "title": "Tile layout", "kind": "choice", "description": "Classic uses fixed controls. Custom tiles lets you choose, resize and reorder the grid below.", "choices": [{"value": "classic", "label": "Classic"}, {"value": "android", "label": "Custom tiles"}]},
    {"path": "sidebar.quickToggles.android.columns", "page": "control", "section": "Quick tiles", "title": "Grid columns", "kind": "number", "description": "Exact column count. The panel expands to fit; tiles can span up to 7 columns and 7 rows.", "min": 1, "max": 12, "step": 1, "scale": 1, "when": [["sidebar.quickToggles.style", "android"]]},
    {"path": "sidebar.quickToggles.android.toggles", "page": "control", "section": "Quick tiles", "title": "Tile order & size", "kind": "tiles", "description": "Changes the custom grid without running any of its actions.", "when": [["sidebar.quickToggles.style", "android"]]},
    {"path": "sidebar.quickSliders.enable", "page": "control", "section": "Quick sliders", "title": "Show quick sliders", "kind": "toggle", "description": "Brightness, output volume and microphone level above the tiles."},
    {"path": "sidebar.quickSliders.showMic", "page": "control", "section": "Quick sliders", "title": "Show microphone slider", "kind": "toggle", "when": [["sidebar.quickSliders.enable", true]]},
    {"path": "sidebar.quickSliders.showVolume", "page": "control", "section": "Quick sliders", "title": "Show volume slider", "kind": "toggle", "when": [["sidebar.quickSliders.enable", true]]},
    {"path": "sidebar.quickSliders.showBrightness", "page": "control", "section": "Quick sliders", "title": "Show brightness slider", "kind": "toggle", "when": [["sidebar.quickSliders.enable", true]]},
    {"path": "screenSnip.savePath", "page": "capture", "section": "Save & search images", "title": "Screenshot folder", "kind": "text", "description": "Leave empty to copy screenshots to the clipboard only."},
    {"path": "sounds.battery", "page": "general", "section": "Event sounds", "title": "Battery sounds", "kind": "toggle"},
    {"path": "sounds.pomodoro", "page": "general", "section": "Event sounds", "title": "Focus timer sounds", "kind": "toggle"},
    {"path": "sounds.theme", "page": "general", "section": "Event sounds", "title": "Sound theme", "kind": "text"},
    {"path": "time.format", "page": "general", "section": "Time & date", "title": "Clock time format", "kind": "text"},
    {"path": "time.shortDateFormat", "page": "general", "section": "Time & date", "title": "Short date format", "kind": "text"},
    {"path": "time.dateWithYearFormat", "page": "general", "section": "Time & date", "title": "Date with year format", "kind": "text"},
    {"path": "time.dateFormat", "page": "general", "section": "Time & date", "title": "Date format", "kind": "text"},
    {"path": "time.pomodoro.breakTime", "page": "general", "section": "Focus timer", "title": "Short break duration", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "s"},
    {"path": "time.pomodoro.cyclesBeforeLongBreak", "page": "general", "section": "Focus timer", "title": "Cycles before long break", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1},
    {"path": "time.pomodoro.focus", "page": "general", "section": "Focus timer", "title": "Focus session duration", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "s"},
    {"path": "time.pomodoro.longBreak", "page": "general", "section": "Focus timer", "title": "Long break duration", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "s"},
    {"path": "time.secondPrecision", "page": "general", "section": "Time & date", "title": "Show seconds on the clock", "kind": "toggle"},
    {"path": "updates.enableCheck", "keywords": "poll polling package refresh", "page": "advanced", "section": "Update indicators", "title": "Enable update checks", "kind": "toggle", "description": "Check Arch repository updates for the Waffle bar indicator. Does not install updates; the ii layout has no update indicator."},
    {"path": "updates.checkInterval", "page": "advanced", "section": "Update indicators", "title": "Update check interval", "kind": "number", "min": 1, "max": 100000, "step": 1, "scale": 1, "unit": "min", "description": "Time between repository checks. More frequent checks do not make the interface faster."},
    {"path": "updates.adviseUpdateThreshold", "page": "advanced", "section": "Update indicators", "title": "Update suggestion threshold", "kind": "number", "min": 1, "max": 100000, "step": 1, "scale": 1, "suffix": "packages", "description": "Show the Waffle update indicator when more than this many repository packages have updates."},
    {"path": "updates.stronglyAdviseUpdateThreshold", "page": "advanced", "section": "Update indicators", "title": "Strong update warning threshold", "kind": "number", "min": 1, "max": 100000, "step": 1, "scale": 1, "suffix": "packages", "description": "Use the warning color above this package count. The count does not measure update urgency or security severity."},
    {"path": "wallpaperSelector.useSystemFileDialog", "page": "wallpaper", "section": "Wallpaper picker", "title": "Use the system wallpaper dialog", "kind": "toggle", "description": "Choose between the shell picker and the platform file dialog."},
    {"path": "windows.showTitlebar", "page": "advanced", "section": "Shell window decorations", "title": "Show title bar", "kind": "toggle"},
    {"path": "windows.centerTitle", "page": "advanced", "section": "Shell window decorations", "title": "Center window titles", "kind": "toggle"},
    {"path": "hacks.arbitraryRaceConditionDelay", "page": "advanced", "section": "Other preferences", "title": "Deferred shell action delay", "kind": "number", "min": 0, "max": 10000, "step": 1, "scale": 1, "unit": "ms", "description": "Debounce clipboard and theme refreshes, and settle dragged overview windows. 100 ms avoids a noticeable one-second wait."},
    {"path": "workSafety.enable.wallpaper", "page": "advanced", "section": "Contextual privacy", "title": "Hide sensitive wallpapers", "kind": "toggle"},
    {"path": "workSafety.enable.clipboard", "page": "advanced", "section": "Contextual privacy", "title": "Hide clipboard images from sensitive sources", "kind": "toggle"},
    {"path": "workSafety.triggerCondition.networkNameKeywords", "page": "advanced", "section": "Contextual privacy", "title": "Network name keywords", "kind": "lines"},
    {"path": "workSafety.triggerCondition.fileKeywords", "page": "advanced", "section": "Contextual privacy", "title": "File keywords", "kind": "lines"},
    {"path": "workSafety.triggerCondition.linkKeywords", "page": "advanced", "section": "Contextual privacy", "title": "Link keywords", "kind": "lines"},
    {"path": "waffles.tweaks.switchHandlePositionFix", "page": "advanced", "section": "Alternate shell", "title": "Switch handle position fix", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.tweaks.smootherMenuAnimations", "page": "advanced", "section": "Alternate shell", "title": "Smoother menu animations", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.tweaks.smootherSearchBar", "page": "advanced", "section": "Alternate shell", "title": "Smoother search bar", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.bar.bottom", "page": "advanced", "section": "Alternate shell", "title": "Place the Waffle bar at the bottom", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.bar.leftAlignApps", "page": "advanced", "section": "Alternate shell", "title": "Left align apps", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.actionCenter.toggles", "page": "advanced", "section": "Alternate shell", "title": "Action center toggles", "kind": "lines", "when": [["panelFamily", "waffle"]]},
    {"path": "waffles.calendar.force2CharDayOfWeek", "page": "advanced", "section": "Alternate shell", "title": "Use two-letter weekday names", "kind": "toggle", "when": [["panelFamily", "waffle"]]},
    {"path": "screenRecord.savePath", "page": "capture", "section": "Save & search images", "title": "Recording folder", "kind": "text", "description": "Folder used by the shell recording helper and its Open recordings folder action."}
];

var retired = {
  "bar.workspaces.showNumberDelay": "Workspace numbers now follow the current bar behavior.",
  "language.translator.engine": "The translator backend does not read this setting.",
  "sidebar.booru.allowNsfw": "Image-provider filtering is owned by the service state.",
  "sidebar.booru.defaultProvider": "The provider is selected in the sidebar and persisted separately."
};
var managed = {
  "cryod.enabled": "CryoD desktop integration",
  "cryod.protectForeground": "CryoD focused workload protection",
  "cryod.protectVisible": "CryoD visible window protection",
  "cryod.groupLaunches": "CryoD application launch groups",
  "cryod.freezeSuggestions": "CryoD automatic app freezing suggestions",
  "background.wallpaperPath": "Wallpaper chooser",
  "background.thumbnailPath": "Generated wallpaper thumbnail"
};

function canonicalPage(id) { return ["effects", "fonts"].indexOf(id) >= 0 ? "design" : id; }
function page(id) { id = canonicalPage(id); return pages.find(function(p) { return p.id === id; }) || pages[0]; }
var searchText = new WeakMap();
var timingWords = "time timing timings timer timers delay delays poll polls polling interval intervals duration durations timeout timeouts wait waiting refresh cadence frequency period debounce sampling";
var loudnessInterval = {path:"musicLoudness.autoInterval", provider:"loudness", page:"audio", section:"Music loudness", title:"Automatic loudness check interval", kind:"choice", unit:"s", choices:[{value:15,label:"15 seconds"},{value:30,label:"30 seconds"},{value:60,label:"60 seconds"}]};
var animationDuration = {path:"effects.animationDuration", provider:"tempo", page:"design", section:"Animation", title:"Animation duration", kind:"number", suffix:"%", min:50, max:160, step:1, scale:1, description:"Percentage of the animation profile duration. Use Apply to save design edits."};
var ambientSpeed = {path:"effects.ambientSpeed", provider:"ambient_speed", page:"design", section:"Ambient effects", title:"Aurora animation speed", kind:"number", suffix:"%", min:40, max:200, step:1, scale:1, description:"Speed of the animated aurora. Use Apply to save design edits."};
var externalTimings = [loudnessInterval, animationDuration, ambientSpeed];
function wordsOf(query) {
    var text = (query || "").trim().toLowerCase();
    return text ? text.split(/[\s/,]+/).filter(Boolean) : [];
}
function matchesWords(entry, words) {
    if (!words.length) return true;
    var haystack = searchText.get(entry);
    if (haystack === undefined) {
        haystack = [entry.title, entry.description || "", entry.keywords || "", entry.section || "", entry.path || "", entry.suffix || "", entry.unit || "", timeUnits[entry.unit] || "", entry.unit || entry.provider ? timingWords : "", page(entry.page).title].join(" ").toLowerCase();
        searchText.set(entry, haystack);
    }
    return words.every(function(word) { return haystack.indexOf(word) >= 0; });
}
function matches(entry, query) { return matchesWords(entry, wordsOf(query)); }
function matchingDestinations(query) {
    var words = wordsOf(query);
    return words.length ? destinations.filter(function(e) { return matchesWords(e, words); }) : [];
}
function searchGroups(query) {
    var words = wordsOf(query);
    if (!words.length) return [];
    var groups = new Map();
    function add(entry, field) {
        if (!matchesWords(entry, words)) return;
        var id = canonicalPage(entry.page);
        if (!groups.has(id)) groups.set(id, {page:id, title:page(id).title, entries:[], timings:[], links:[]});
        groups.get(id)[field].push(entry);
    }
    entries.forEach(function(e) { add(e, "entries"); });
    externalTimings.forEach(function(e) { add(e, "timings"); });
    destinations.forEach(function(e) { add(e, "links"); });
    return pages.filter(function(p) { return groups.has(p.id); }).map(function(p) { return groups.get(p.id); });
}
function sections(pageId, query) {
    var groups = [];
    var byKey = new Map();
    var words = wordsOf(query);
    entries.forEach(function(e) {
        if ((pageId && e.page !== pageId) || !matchesWords(e, words)) return;
        var key = e.page + "/" + e.section;
        var group = byKey.get(key);
        if (!group) { group = {key:key, title:e.section, page:e.page, entries:[]}; groups.push(group); byKey.set(key, group); }
        group.entries.push(e);
    });
    var order = {
        wallpaper: ["Wallpaper discovery", "Offline & preview queue", "Saved wallpaper storage", "Wallpaper picker"],
        control: ["Quick tiles", "Quick sliders", "Panel loading", "Corner gestures", "On-screen keyboard"],
        bar: ["Bar layout", "Workspace indicators", "Resource monitoring", "Resource warnings", "System tray", "Utility buttons", "Auto-hide", "Bar weather", "Bar tooltips"]
    }[pageId];
    if (order) groups.sort(function(a,b) { return order.indexOf(a.title) - order.indexOf(b.title); });
    return groups;
}

var destinations = [
    {page:"launcher", title:"Emergency terminal shortcut", description:"Super Ctrl Enter recovery rescue lightweight foot Bash shell memory pressure independent Kitty"},
    {page:"control", title:"VRR by monitor", description:"display variable refresh rate FreeSync Adaptive Sync per monitor Off Always fullscreen games video global policy GPU actual state flicker"},
    {page:"agents", title:"AI sessions and workloads", description:"Codex agent session thread ID PID CPU RAM RSS swap virtual memory child process tmux Haven SSH terminal Kitty monitor"},
    {page:"agents", title:"Codex session notifications", description:"Codex notification full response expand ellipsis dots open focus terminal Kitty tmux detached resume reopen session master off"},
    {page:"storage", title:"Disk space alerts & build cleanup", description:"storage disk disks NVMe SSD SATA HDD Btrfs btrfs-stat capacity free space full warning forecast Gradle compiler caches trash cleanup preview master off"},
    {page:"cryod", title:"CryoD desktop integration", description:"memory foreground focus mode cpu priority gpu latency boost visible windows monitor workload protection session bridge master off app application launcher groups freeze freezer allow deny preference consent"},
    {page:"company", title:"PC reconnection alerts", description:"remote Windows PC SSH online reconnect connection monitor polling desktop notification watcher arm stop"},
    {page:"company", title:"Company password reset alerts", description:"Imak Microsoft 365 Entra SSPR password reset recovery registration audit logs notifications master toggle"},
    {page:"memory", title:"OOM kill notifications", description:"memory pressure kernel systemd-oomd PID killed LMKD log notifications alerts history"},
    {page:"audio", title:"Eden volume boost widget", description:"Mario Kart MK8DX double-click +12 dB game only loudness current preset reset"},
    {page:"audio", title:"Music loudness controls", description:"quiet songs gain boost volume plus minus limiter EasyEffects match LUFS target step reset master off app picker Firefox browser selected application auto match loudness automatic normalization normalisation interval"},
    {page:"memory", title:"Memory locks, RSS & process search", description:"noswap swap RAM RSS resident memory large usage sort PID process name search suggested lock unlock release group tree protection reminders locked paging saved names future launches startup automatic matching shared group permissions mpv qs easyeffects pipewire wireplumber draft batch apply all discard selection"},
    {page:"mail", title:"Mail accounts and smart actions", description:"Thunderbird email notifications 2FA OTP verification codes links add accounts master toggle"},
    {page:"design", title:"Color mode, palette & desktop effects", description:"Matugen Monet Material light dark palette accent saved looks, blur, glow, borders, opacity, transparency, springs, animation, workspace motion and presets"},
    {page:"fonts", title:"Desktop font profiles", description:"fontctl presets, typefaces, font preview, compact 10 pt, system fonts, Kitty fonts"},
    {page:"audio", title:"Automatic music EQ", description:"James Control Spotify Jukebox mpv osu osu!lazer game audio song artist genre automatic EasyEffects presets music EQ on off"},
    {page:"audio", title:"Spatial audio for mpv", description:"Dolby Atmos binaural surround headphones multichannel m4a mpv F8 spatial switch on off"},
    {page:"audio", title:"EasyEffects presets", description:"Equalizer, music, audio processing, output preset and EasyEffects"},
    {page:"wallpaper", title:"Wallpaper discovery", description:"Choose wallpaper, download, discover, offline queue, rotation, restore, saved library"}
];
