-- Resume enabled geometry restoration on login and repair a stopped listener
-- on reload. This runs out of process and never rearranges existing windows.
if os.getenv("HYPRLAND_MIGRATION_TEST") ~= "1" then
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/geo-daemon.sh --ensure")
end
