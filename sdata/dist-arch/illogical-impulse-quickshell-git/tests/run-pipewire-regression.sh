#!/usr/bin/env bash
# Remove/recreate private virtual nodes; never connects to the desktop audio server.
set -euo pipefail
binary=$(readlink -f -- "${1:-/usr/bin/quickshell}")
base=$(dirname -- "$(readlink -f -- "$0")")
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/qs-pipewire-regression.XXXXXX")
cp "$base/pipewire.conf" "$base/pipewire-regression.py" "$run_dir/"
cp -r "$base/probe" "$run_dir/"
mkdir -m 700 "$run_dir/pipewire-runtime"
PIPEWIRE_RUNTIME_DIR="$run_dir/pipewire-runtime" pipewire -c "$run_dir/pipewire.conf" > "$run_dir/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; printf "Receipts: %s\n" "$run_dir"' EXIT
for ((i=0; i<50; i++)); do
    [[ -S "$run_dir/pipewire-runtime/qs-upgrade-test" ]] && break
    kill -0 "$server_pid"
    sleep 0.1
done
python3 -u "$run_dir/pipewire-regression.py" "$binary" candidate
