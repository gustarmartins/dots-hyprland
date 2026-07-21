hl.env("EDITOR", "kate")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
hl.env("MOZ_WAYLAND_USE_VAAPI", "1")
hl.env("GTK_IM_MODULE", "xim")

-- Keep the system Fontconfig/FreeType defaults. The previous forced TrueType
-- interpreter and stem-darkening override was absent in Hyprland safe mode,
-- whose text rendering is visibly sharper on the AOC display.
