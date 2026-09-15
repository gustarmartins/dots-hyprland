#!/usr/bin/env bash
set -euo pipefail
# Use the shared, verified profile without disabling the output or moving its
# workspaces. Bit depth is not a sharpness control; this AOC advertises 8 bpc.
exec "$HOME/.local/bin/refresh-displays" cycle DP-1
