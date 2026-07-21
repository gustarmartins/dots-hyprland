#!/usr/bin/env bash
# Install the staged Lua migration without changing the running config manager.

set -euo pipefail

check_only=false
if (( $# == 2 )) && [[ "$1" == "--check" ]]; then
    check_only=true
    shift
elif (( $# != 1 )); then
    echo "Usage: $0 [--check] /path/to/pre-lua-backup" >&2
    exit 2
fi

backup_dir="${1%/}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_ref="pre-lua-migration-20260721"
manager_path="dots/.config/hypr/hyprland.lua"

for required in hypr quickshell-ii local-bin hypr-mcp system runtime; do
    if [[ ! -e "$backup_dir/$required" ]]; then
        echo "Incomplete rollback backup: missing $backup_dir/$required" >&2
        exit 1
    fi
done

if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    echo "Refusing to install from a dirty migration worktree: $repo_root" >&2
    exit 1
fi

git -C "$repo_root" rev-parse --verify --quiet "$baseline_ref^{commit}" >/dev/null || {
    echo "Missing protected baseline ref: $baseline_ref" >&2
    exit 1
}

if [[ "$(git -C "$repo_root" rev-parse HEAD)" != \
    "$(git -C "$repo_root" rev-parse '@{upstream}')" ]]; then
    echo "Refusing to install a migration commit that is not pushed to its upstream branch." >&2
    exit 1
fi

mapfile -t deleted_paths < <(
    git -C "$repo_root" diff --name-only --diff-filter=D "$baseline_ref..HEAD" -- \
        dots/.config/hypr dots/.config/quickshell/ii dots/.local system
)
if (( ${#deleted_paths[@]} != 0 )); then
    printf 'Refusing an install with unhandled deleted paths:\n' >&2
    printf '  %s\n' "${deleted_paths[@]}" >&2
    exit 1
fi

preflight_dir="$(mktemp -d /tmp/hypr-lua-install.XXXXXX)"
cleanup() {
    if [[ "$preflight_dir" == /tmp/hypr-lua-install.* ]]; then
        rm -rf -- "$preflight_dir"
    fi
}
trap cleanup EXIT

mkdir -p "$preflight_dir/.config"
rsync -a -- "$repo_root/dots/.config/hypr/" "$preflight_dir/.config/hypr/"
find "$repo_root/dots/.config/hypr" -type f -name '*.lua' -print0 | xargs -0 -n1 luac -p
env HOME="$preflight_dir" HYPRLAND_MIGRATION_TEST=1 \
    Hyprland --verify-config --config "$preflight_dir/.config/hypr/hyprland.lua"
env HOME="$preflight_dir" \
    Hyprland --verify-config --config "$preflight_dir/.config/hypr/hyprland.lua"

mapfile -t changed_paths < <(
    git -C "$repo_root" diff --name-only --diff-filter=ACMRT "$baseline_ref..HEAD" -- \
        dots/.config/hypr dots/.config/quickshell/ii dots/.local system
)

manager_source=""
for path in "${changed_paths[@]}"; do
    if [[ "$path" == "$manager_path" ]]; then
        manager_source="$repo_root/$path"
        break
    fi
done

if [[ -z "$manager_source" ]]; then
    echo "Migration entrypoint is absent from the staged diff." >&2
    exit 1
fi

if $check_only; then
    echo "Lua migration preflight passed for $(git -C "$repo_root" rev-parse --short HEAD)."
    echo "Install manifest: ${#changed_paths[@]} files; rollback source: $backup_dir"
    exit 0
fi

for path in "${changed_paths[@]}"; do
    source_path="$repo_root/$path"
    mode="$(stat -c '%a' "$source_path")"

    if [[ "$path" == "$manager_path" ]]; then
        continue
    fi

    case "$path" in
        dots/*)
            target_path="$HOME/${path#dots/}"
            install -D -m "$mode" -- "$source_path" "$target_path"
            ;;
        system/*)
            target_path="/${path#system/}"
            sudo install -D -m "$mode" -- "$source_path" "$target_path"
            ;;
    esac
done

sudo systemctl daemon-reload

manager_target="$HOME/.config/hypr/hyprland.lua"
manager_staged="$manager_target.codex-new"
install -D -m 644 -- "$manager_source" "$manager_staged"
mv -T -- "$manager_staged" "$manager_target"

echo "Lua migration payload installed from $(git -C "$repo_root" rev-parse --short HEAD)."
echo "Rollback source: $backup_dir"
echo "Log out and start a new Hyprland session to activate it."
echo "Do not use 'hyprctl reload full-reset' to cross config managers on Hyprland 0.56.0."
