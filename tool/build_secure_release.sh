#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep Dart symbol files outside the distributed bundle and source repository.
focusforge_symbols_dir="${FOCUSFORGE_SYMBOLS_DIR:-../focusforge-symbols/$(date -u +%Y%m%dT%H%M%SZ)}"
install -d -m 700 "$focusforge_symbols_dir"
flutter build appbundle "$@" --release --obfuscate --split-debug-info="$focusforge_symbols_dir"
# Flutter's display-name picker can select an older named bundle left in this
# directory. Copy the newly produced AGP output explicitly, never that picker.
focusforge_version="$(sed -n 's/^version: //p' pubspec.yaml)"
focusforge_bundle="build/app/outputs/bundle/release/focusforge-${focusforge_version%+*}-${focusforge_version#*+}.aab"
cp build/app/outputs/bundle/release/app-release.aab "$focusforge_bundle"
printf 'Verified release output: %s\nPrivate Dart symbols: %s\n' "$focusforge_bundle" "$focusforge_symbols_dir"
