#!/usr/bin/env bash
# Usage: time-limit.sh <seconds> <command...>
# Runs the command and kills it, children included, once it has run for <seconds>; exits 124 then.
set -euo pipefail

limit=$1
shift

set -m # the command gets its own process group, so the kill reaches the test runner it spawns
"$@" &
pid=$!
set +m

(sleep "$limit" && kill -TERM -- "-$pid") 2>/dev/null &
watchdog=$!

status=0
wait "$pid" || status=$?
if ! kill -0 "$watchdog" 2>/dev/null; then
    echo "error: exceeded the ${limit}s limit: $*" >&2
    exit 124
fi
pkill -P "$watchdog" || true
exit "$status"
