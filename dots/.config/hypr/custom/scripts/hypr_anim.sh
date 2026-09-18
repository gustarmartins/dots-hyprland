#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Hyprland Animation Switcher for Rofi
# -----------------------------------------------------------------------------
# Strict Mode:
# -u: Error on unset variables (catches typos)
# -o pipefail: Pipeline fails if any command fails
set -u
set -o pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
# Use readonly for constants to prevent accidental overwrites
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly ANIM_DIR="$CONFIG_DIR/hypr/custom/animations"
readonly LINK_DIR="$ANIM_DIR/active"
readonly DEST_FILE="$LINK_DIR/active.lua"
readonly STATE_FILE="$CONFIG_DIR/hypr/custom/animations/state"
readonly FALLBACK_ANIM="horizontal_dusky.lua"

# Visual Assets (Nerd Fonts)
readonly ICON_ACTIVE=""   # Checkmark
readonly ICON_FILE=""     # File
readonly ICON_ERROR=""    # Warning

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

notify_user() {
    local title="$1"
    local message="$2"
    local urgency="${3:-low}"
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Hyprland Animations" "$title" "$message"
    fi
}

apply_animation() {
    local name="${1##*/}" output
    if ! output=$("$HOME/.local/bin/desktop-effects" animation "$name" 2>&1); then
        notify_user "Animation not applied" "$output" "critical"
        return 1
    fi
}

# Sanitize filenames for Rofi's Pango markup
escape_markup() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    printf '%s' "$s"
}

# -----------------------------------------------------------------------------
# EXECUTION LOGIC (Selection Made or Flags)
# -----------------------------------------------------------------------------

# Handle the --current restoration flag (with fallback logic)
if [[ "${1:-}" == "--current" ]]; then
    target_anim=""

    # 1. Attempt to read existing valid state
    if [[ -f "$STATE_FILE" ]]; then
        saved_anim=$(<"$STATE_FILE")
        if [[ "$saved_anim" == *.conf ]]; then
            saved_anim="${saved_anim%.conf}.lua"
        fi
        if [[ "$saved_anim" != */* ]]; then
            saved_anim="$ANIM_DIR/$saved_anim"
        fi
        if [[ -n "$saved_anim" && -f "$saved_anim" ]]; then
            target_anim="$saved_anim"
        fi
    fi

    # 2. Fallback if no valid state was found
    if [[ -z "$target_anim" ]]; then
        target_anim="$ANIM_DIR/$FALLBACK_ANIM"
        if [[ ! -f "$target_anim" ]]; then
            notify_user "Error" "Fallback animation missing: $target_anim" "critical"
            exit 1
        fi
    fi

    # Startup restoration must not switch a saved custom-motion look to profile mode.
    if ! output=$("$HOME/.local/bin/desktop-effects" refresh 2>&1); then
        notify_user "Animation restore failed" "$output" "critical"
        exit 1
    fi
    exit 0
fi

selection="${ROFI_INFO:-}"

# Fallback: Handle manual CLI usage or older Rofi versions
if [[ -z "$selection" && -n "${1:-}" ]]; then
    # Use printf to safely handle inputs starting with dashes
    clean_name=$(printf '%s' "$1" | sed 's/<[^>]*>//g' | xargs -r)
    selection="$ANIM_DIR/$clean_name"
fi

if [[ -n "$selection" ]]; then
    if [[ ! -f "$selection" ]]; then
        notify_user "Error" "File not found: $selection" "critical"
        exit 1
    fi

    if apply_animation "$selection"; then
        notify_user "Animation selected" "${selection##*/} — fine-tune in Super+I > Desktop effects."
        exit 0
    fi
    exit 1
fi

# -----------------------------------------------------------------------------
# MENU GENERATION (No Selection)
# -----------------------------------------------------------------------------

# Rofi Protocol Headers
printf '\0prompt\x1fAnimations\n'
printf '\0markup-rows\x1ftrue\n'
printf '\0no-custom\x1ftrue\n'
printf '\0message\x1fChoose base motion; visual effects stay active. Fine-tune in Super+I.\n'

# Validate Source Directory
if [[ ! -d "$ANIM_DIR" ]]; then
    printf '%s\0icon\x1f%s\x1finfo\x1fignore\n' "Directory Missing" "$ICON_ERROR"
    exit 0
fi

# Gather Lua profiles safely
shopt -s nullglob
files=("$ANIM_DIR"/*.lua)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
    printf '%s\0icon\x1f%s\x1finfo\x1fignore\n' "No Lua profiles found" "$ICON_ERROR"
    exit 0
fi

# Determine Active File via Content Comparison
active_index=-1

if [[ -f "$DEST_FILE" ]]; then
    for i in "${!files[@]}"; do
        if cmp -s "${files[$i]}" "$DEST_FILE"; then
            active_index=$i
            break
        fi
    done
fi

# Tell Rofi which row to highlight
if (( active_index >= 0 )); then
    printf '\0active\x1f%d\n' "$active_index"
fi

# Generate Rows
for i in "${!files[@]}"; do
    file="${files[$i]}"
    filename="${file##*/}"
    
    escaped_name=$(escape_markup "$filename")

    if (( i == active_index )); then
        printf "<span weight='bold'>%s</span> <span size='small' style='italic'>(Selected)</span>\0icon\x1f%s\x1finfo\x1f%s\n" \
            "$escaped_name" "$ICON_ACTIVE" "$file"
    else
        printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' \
            "$escaped_name" "$ICON_FILE" "$file"
    fi
done

exit 0
