#!/usr/bin/env bash
curr_workspace="$(hyprctl activeworkspace -j | jq -r ".id")"
dispatcher="$1"
shift ## The target is now in $1, not $2

if [[ -z "${dispatcher}" || "${dispatcher}" == "--help" || "${dispatcher}" == "-h" || -z "$1" ]]; then
  echo "Usage: $0 <dispatcher> <target>"
  exit 1
fi
if [[ "$1" == *"+"* || "$1" == *"-"* ]]; then ## Is this something like r+1 or -1?
  target_workspace="$1"
elif [[ "$1" =~ ^[0-9]+$ ]]; then ## Is this just a number?
  target_workspace=$((((curr_workspace - 1) / 10 ) * 10 + $1))
else
  target_workspace="$1" ## In case the target is a string, required for special workspaces.
fi

# JSON strings are valid Lua strings and prevent special-workspace names from
# becoming executable Lua when this compatibility helper is called directly.
quoted_workspace=$(jq -Rn --arg value "$target_workspace" '$value | tojson')

case "$dispatcher" in
  workspace)
    hyprctl dispatch "hl.dsp.focus({ workspace = $quoted_workspace })"
    ;;
  movetoworkspacesilent)
    hyprctl dispatch "hl.dsp.window.move({ workspace = $quoted_workspace, follow = false })"
    ;;
  *)
    echo "Unsupported Lua dispatcher compatibility mapping: $dispatcher" >&2
    exit 2
    ;;
esac
