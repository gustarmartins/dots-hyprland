#!/usr/bin/env bash
# Compatibility entry point; shared controller owns geometry and float state.
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/window-geometry.py" save-app
