-- Aether Fusion: a physically coherent flagship profile inspired by the
-- spatial springs of iOS/macOS, One UI's decisive exits, and Material's
-- emphasized motion. Spatial movement uses real springs; opacity does not
-- overshoot, so the result feels alive without flashing or looking rubbery.
hl.config({ animations = { enabled = true } })

-- Spatial springs. Keep mass at 1 and vary stiffness/dampening by role.
hl.curve("aetherOpen", {
    type = "spring",
    mass = 1.0,
    stiffness = 190.0,
    dampening = 20.0,
})
hl.curve("aetherMove", {
    type = "spring",
    mass = 1.0,
    stiffness = 250.0,
    dampening = 28.0,
})
hl.curve("aetherSpace", {
    type = "spring",
    mass = 1.0,
    stiffness = 155.0,
    dampening = 20.0,
})
hl.curve("aetherSheet", {
    type = "spring",
    mass = 1.0,
    stiffness = 215.0,
    dampening = 23.0,
})

-- Optical timing curves. Exits are short and intentional; entrances spend
-- their time settling. This prevents the common "slow desktop" feeling.
hl.curve("aetherReveal", {
    type = "bezier",
    points = {{ 0.12, 0.92 }, { 0.18, 1.0 }},
})
hl.curve("aetherExit", {
    type = "bezier",
    points = {{ 0.40, 0.0 }, { 0.82, 0.20 }},
})
hl.curve("aetherSoft", {
    type = "bezier",
    points = {{ 0.20, 0.80 }, { 0.20, 1.0 }},
})

-- Windows: a visible but restrained 82% scale reveal, followed by a small
-- physical settle. Closing is quicker and shallower, like iOS and One UI.
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.2, spring = "aetherOpen", style = "popin 82%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.4, bezier = "aetherExit", style = "popin 94%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.6, spring = "aetherMove", style = "slide" })

-- Opacity is deliberately decoupled from scale. Content becomes readable
-- early on entry and disappears cleanly before the closing transform ends.
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.6, bezier = "aetherReveal" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.8, bezier = "aetherExit" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.2, bezier = "aetherSoft" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.8, bezier = "aetherSoft" })
hl.animation({ leaf = "fadeGlow", enabled = true, speed = 2.8, bezier = "aetherSoft" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 2.6, bezier = "aetherSoft" })

-- Shell surfaces stay subtler than app windows, preserving their relationship
-- to the screen edge while still giving launchers and panels physical depth.
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.8, spring = "aetherSheet", style = "popin 92%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.2, bezier = "aetherExit", style = "popin 96%" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.2, bezier = "aetherReveal" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.7, bezier = "aetherExit" })
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 1.8, bezier = "aetherReveal" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.4, bezier = "aetherExit" })
hl.animation({ leaf = "fadeDpms", enabled = true, speed = 4.0, bezier = "aetherSoft" })

-- Spaces use reduced travel plus cross-fade: macOS-like continuity without a
-- full-screen shove. The special workspace rises independently like a sheet.
hl.animation({ leaf = "workspaces", enabled = true, speed = 5.6, spring = "aetherSpace", style = "slidefade 32%" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 5.6, spring = "aetherSpace", style = "slidefade 32%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 4.8, spring = "aetherSpace", style = "slidefade 32%" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 4.6, spring = "aetherSheet", style = "slidefadevert 22%" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2.8, bezier = "aetherExit", style = "slidefadevert 16%" })

-- Finishing details. Avoid a looping angle animation: it forces continuous
-- redraws even while the desktop is idle.
hl.animation({ leaf = "border", enabled = true, speed = 2.4, bezier = "aetherSoft" })
hl.animation({ leaf = "borderangle", enabled = false })
hl.animation({ leaf = "shadowangle", enabled = false })
hl.animation({ leaf = "glowangle", enabled = false })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 3.4, spring = "aetherMove" })
