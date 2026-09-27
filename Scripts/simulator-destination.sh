#!/usr/bin/env bash
# Prints an xcodebuild -destination string for the newest available iPhone simulator.
# Override with SIMULATOR_DESTINATION="platform=iOS Simulator,name=iPhone 17".
set -euo pipefail

if [[ -n "${SIMULATOR_DESTINATION:-}" ]]; then
    echo "$SIMULATOR_DESTINATION"
    exit 0
fi

udid=$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
ios = sorted(
    (k for k in runtimes if ".SimRuntime.iOS-" in k),
    key=lambda k: [int(p) for p in k.rsplit("iOS-", 1)[1].split("-")],
    reverse=True,
)
for runtime in ios:
    for device in runtimes[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator found")
')
echo "platform=iOS Simulator,id=$udid"
