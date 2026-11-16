#!/bin/bash
# Queues a burst, kills the test process, relaunches and checks every event arrives once.
# Usage: Scripts/queue_e2e/run.sh <simulator-udid>
set -u
SIM=${1:?simulator udid}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mktemp -d)
PORT=8765
BASE="http://127.0.0.1:$PORT"
DD="$OUT/dd"

run_phase() {
  env TEST_RUNNER_LR_E2E_PHASE="$1" TEST_RUNNER_LINKRUNNER_DEBUG_BASE_URL="$BASE" TEST_RUNNER_LR_E2E_DONE_FILE="$OUT/done" \
    xcodebuild test -scheme LinkrunnerKit-Package -destination "id=$SIM" -derivedDataPath "$DD" \
    -only-testing:"LinkrunnerKitTests/QueueEndToEndTests/$2" > "$OUT/$1.log" 2>&1
}

cd "$ROOT"
python3 Scripts/queue_e2e/mock.py $PORT "$OUT/burst.jsonl" events503 & MOCK=$!
sleep 1
run_phase burst testBurstThenKill
kill $MOCK; sleep 1

python3 Scripts/queue_e2e/mock.py $PORT "$OUT/drain.jsonl" ok & MOCK=$!
sleep 1
( while :; do
    python3 Scripts/queue_e2e/check.py "$OUT/drain.jsonl" --quiet && { touch "$OUT/done"; break; }
    sleep 1
  done ) & WATCH=$!
run_phase drain testRelaunchDrains
sleep 2; kill $MOCK $WATCH 2>/dev/null

grep -h 'LR_E2E' "$OUT/burst.log"
python3 Scripts/queue_e2e/check.py "$OUT/drain.jsonl"
