#!/usr/bin/env bash
# Compatibility path. No watcher or automatic discovery remains here.
exec "${ANDROID_ADB_DEMAND_TOOL:-${HOME}/.local/bin/android-adb-on-demand}" "$@"
