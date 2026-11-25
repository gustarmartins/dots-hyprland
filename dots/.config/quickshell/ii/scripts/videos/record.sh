#!/usr/bin/env bash
set -euo pipefail

# Delegate to recordctl (hardware KMS gpu-screen-recorder by default, with wf-recorder fallback).
RECORDCTL="$HOME/.local/bin/recordctl"

ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0

for ((i=0; i<${#ARGS[@]}; i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
            ((i++))
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

if "$RECORDCTL" is-recording; then
    exec "$RECORDCTL" stop >/dev/null
fi

CMD=("$RECORDCTL" start)
if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
    CMD+=(--fullscreen)
else
    if [[ -n "$MANUAL_REGION" ]]; then
        region="$MANUAL_REGION"
    else
        if ! region="$(slurp 2>&1)"; then
            notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
            exit 1
        fi
    fi
    CMD+=(--region "$region")
fi

if [[ $SOUND_FLAG -eq 1 ]]; then
    CMD+=(--sound)
else
    CMD+=(--no-sound)
fi

exec "${CMD[@]}" >/dev/null
