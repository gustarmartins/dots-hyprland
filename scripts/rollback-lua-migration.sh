#!/usr/bin/env bash
# Restore a local pre-migration backup without changing managers in-process.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /absolute/path/to/pre-lua-backup" >&2
    exit 2
fi

backup_dir=$(realpath -- "$1")
for required in hypr quickshell-ii local-bin hypr-mcp system; do
    [[ -e "$backup_dir/$required" ]] || {
        echo "Incomplete rollback backup: missing $backup_dir/$required" >&2
        exit 1
    }
done

# This one selector is what makes Hyprland prefer Lua over hyprland.conf.
rm -f -- "$HOME/.config/hypr/hyprland.lua"

rsync -a -- "$backup_dir/hypr/" "$HOME/.config/hypr/"
rsync -a -- "$backup_dir/quickshell-ii/" "$HOME/.config/quickshell/ii/"
rsync -a -- "$backup_dir/local-bin/" "$HOME/.local/bin/"
rsync -a -- "$backup_dir/hypr-mcp/" "$HOME/.local/share/hypr-mcp/"

sudo install -m 755 "$backup_dir/system/fix-display-resume.sh" /usr/local/bin/fix-display-resume.sh
sudo install -m 755 "$backup_dir/system/fix-dpms-resume.sh" /usr/local/bin/fix-dpms-resume.sh
sudo install -m 644 "$backup_dir/system/display-resume-fix.service" /etc/systemd/system/display-resume-fix.service
sudo systemctl daemon-reload

echo "Legacy Hyprland configuration restored from $backup_dir"
echo "Restart the Hyprland session to switch back to hyprlang."
echo "Do not use 'hyprctl reload full-reset' on Hyprland 0.56.0: it can abort while flushing config caches."
