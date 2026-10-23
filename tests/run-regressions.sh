#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
regression_dir="$(mktemp -d -t arswidget-regressions)"
trap 'rm -rf "$regression_dir"' EXIT
compile_and_run() {
    regression_name="$1"
    shift
    # Compile one immutable local snapshot. File-provider backed checkouts can
    # change stat metadata while Swift is reading otherwise identical files.
    mkdir -p "$regression_dir/$regression_name-sources"
    for regression_source in "$@"; do
        cp "$regression_source" "$regression_dir/$regression_name-sources/$(basename "$regression_source")"
    done
    swiftc -module-cache-path "${TMPDIR:-/tmp}/arswidget-tests-module-cache" "$regression_dir/$regression_name-sources/"*.swift -o "$regression_dir/$regression_name"
    "$regression_dir/$regression_name"
}
compile_and_run keep-awake ArsWidget/managers/KeepAwakeManager.swift tests/KeepAwakeTests.swift
compile_and_run vocabulary ArsWidget/managers/VocabLearning.swift tests/VocabLearningTests.swift
compile_and_run vocabulary-presentation ArsWidget/managers/VocabLearning.swift tests/VocabPromptPresentationTests.swift
compile_and_run player-volume ArsWidget/managers/PlayerVolumeCommands.swift ArsWidget/helpers/AppleScriptHelper.swift tests/PlayerVolumeTests.swift
compile_and_run clipboard ArsWidget/managers/ClipboardTextReader.swift ArsWidget/managers/ClipboardManager.swift tests/ClipboardManagerTests.swift
python3 tests/run-vocab-screen-geometry-tests.py
python3 tests/run-pomodoro-preview.py
python3 tests/run-system-tour-preview.py
