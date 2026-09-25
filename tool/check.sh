#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_apple_identity.py'
flutter build apk --debug
