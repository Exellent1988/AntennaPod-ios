#!/bin/bash
# Run AntennaPodTests on a simulator nobody else uses.
#
# Why: the real-player tests (PlaybackEndToEndTests / PlaybackFixtureTestCase) take 3-10 s each.
# When another agent or developer installs de.danoeh.antennapod.ios on the SAME simulator
# (xcodebuild test / simctl install), installcoordinationd terminates the running app, and the
# test host dies with "Test crashed with signal kill/term" in whatever test happens to be
# running. That was the "random" mid-run kill on the shared simulator (Oct 2026).
#
# Usage: scripts/test-on-private-simulator.sh <name> [extra xcodebuild args...]
set -euo pipefail
NAME="${1:?simulator name, e.g. AP-$USER-tests}"; shift
TYPE="${SIM_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}"
RUNTIME="${SIM_RUNTIME:-$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"]=="iOS" and r["isAvailable"]][-1])')}"
UDID="$(xcrun simctl list devices -j | python3 -c "import json,sys
for ds in json.load(sys.stdin)['devices'].values():
    for d in ds:
        if d['name']=='$NAME' and d['isAvailable']: print(d['udid']); break" | head -1)"
[ -n "$UDID" ] || UDID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")"
xcrun simctl bootstatus "$UDID" -b >/dev/null
cd "$(dirname "$0")/.."
exec xcodebuild test -project AntennaPod.xcodeproj -scheme AntennaPod -destination "id=$UDID" "$@"
