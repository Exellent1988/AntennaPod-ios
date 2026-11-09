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
# Env: TEST_DEFAULT_TIMEOUT (120 s), TEST_MAX_TIMEOUT (300 s), TEST_OVERALL_TIMEOUT (2700 s).
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

# Hygiene (Oct 2026: beeps + crash dialogs on Axel's Mac):
# - serial tests (no parallel clones of the simulator), per-test timeouts, overall timeout;
# - afterwards shut down ONLY this simulator ($UDID) and kill ONLY the xcodebuild started here.
# - never touch CrashReporter / ReportCrash or any other simulator / process.
DEFAULT_TIMEOUT="${TEST_DEFAULT_TIMEOUT:-120}"   # seconds per test
MAX_TIMEOUT="${TEST_MAX_TIMEOUT:-300}"           # hard cap per test
OVERALL_TIMEOUT="${TEST_OVERALL_TIMEOUT:-2700}"  # whole run (45 min)

cleanup() {
    if [ -n "${XCB_PID:-}" ] && kill -0 "$XCB_PID" 2>/dev/null; then
        kill -TERM "$XCB_PID" 2>/dev/null || true
        sleep 5
        kill -0 "$XCB_PID" 2>/dev/null && kill -KILL "$XCB_PID" 2>/dev/null || true
    fi
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

xcodebuild test -project AntennaPod.xcodeproj -scheme AntennaPod -destination "id=$UDID" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$DEFAULT_TIMEOUT" \
    -maximum-test-execution-time-allowance "$MAX_TIMEOUT" \
    "$@" &
XCB_PID=$!

# Overall timeout: watchdog kills only our own xcodebuild.
( sleep "$OVERALL_TIMEOUT"; if kill -0 "$XCB_PID" 2>/dev/null; then
    echo "test-on-private-simulator: overall timeout ${OVERALL_TIMEOUT}s, stopping xcodebuild $XCB_PID" >&2
    kill -TERM "$XCB_PID" 2>/dev/null; fi ) &
WATCHDOG_PID=$!

set +e
wait "$XCB_PID"
STATUS=$?
set -e
kill "$WATCHDOG_PID" 2>/dev/null || true
exit "$STATUS"
