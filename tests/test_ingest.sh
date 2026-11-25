#!/bin/bash
# Offline tests for src/ingest.sh using stand-ins for the macOS tools and the API.
# Run: bash tests/test_ingest.sh   (needs python3)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S="$T/stubs"; mkdir -p "$S" "$T/dl"
cat > "$S/sips" <<'X'
#!/bin/bash
in=""; out=""; while [ $# -gt 0 ]; do case "$1" in --out) out=$2; shift;; -s) shift 2; continue;; -Z) shift;; *) in=$1;; esac; shift; done
cp "$in" "$out"
X
cat > "$S/security" <<'X'
#!/bin/bash
[ -n "${FAKE_KEY:-}" ] && echo "$FAKE_KEY" || exit 44
X
cat > "$S/defaults" <<'X'
#!/bin/bash
exit 1
X
cat > "$S/curl" <<'X'
#!/bin/bash
cfg=$(cat); out=""; while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift;; --data-binary) req=${2#@}; shift;; esac; shift; done
echo "$cfg" | grep -q 'x-api-key: sk-test' || { echo 401; echo '{"error":{"message":"bad key"}}' > "$out"; exit 0; }
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$req" || { echo 400; exit 0; }
cp "$FAKE_RESP" "$out"; echo "${FAKE_CODE:-200}"
X
cat > "$S/plutil" <<'X'
#!/usr/bin/env python3
import json,sys
a=sys.argv; kp=a[a.index('-extract')+1]; f=a[-1]
v=json.load(open(f))
try:
    for k in kp.split('.'):
        v=v[int(k)] if isinstance(v,list) else v[k]
except Exception: sys.exit(1)
print(('true' if v else 'false') if isinstance(v,bool) else v)
X
cat > "$S/stat" <<'X'
#!/usr/bin/env python3
import os,sys; st=os.stat(sys.argv[-1]); print(int(st.st_ctime) if sys.argv[2]=='%c' else st.st_size)
X
chmod +x "$S"/*
export RI_STUB_PATH="$S" RI_DOWNLOADS="$T/dl"
H="$ROOT/src/ingest.sh"; fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $(printf '%q' "$3")"; echo "  got:      $(printf '%q' "$2")"; fail=1; fi; }
resp() { printf '{"content":[{"type":"tool_use","name":"record_receipt","input":%s}]}' "$1" > "$T/resp.json"; }
printf 'fakeimage' > "$T/r.heic"; export FAKE_RESP="$T/resp.json"

export FAKE_KEY=sk-test
resp '{"is_receipt":true,"multiple_receipts":false,"business":"Home Depot","total":"$1,042.18","date":"2026-11-23","items_summary":"Lumber,\ndeck screws","card_last4":"****4417"}'
check "good receipt" "$(bash "$H" process "$T/r.heic")" $'OK\nHome Depot\n104218\n2026-11-23\nLumber, deck screws\n4417\nEND'
resp '{"is_receipt":true,"multiple_receipts":false,"business":"Shell","total":"40","date":"2026-11-23","items_summary":"Gas","card_last4":""}'
check "no card, whole dollars" "$(bash "$H" process "$T/r.heic")" $'OK\nShell\n4000\n2026-11-23\nGas\n\nEND'
resp '{"is_receipt":true,"multiple_receipts":false,"business":"Shell","total":"","date":"2026-11-23","items_summary":"Gas","card_last4":""}'
check "missing total" "$(bash "$H" process "$T/r.heic")" $'NEEDSREVIEW\nCouldn\'t read the total.\nEND'
resp '{"is_receipt":true,"multiple_receipts":false,"business":"Shell","total":"12.00","date":"11/23/2026","items_summary":"Gas","card_last4":""}'
check "bad date" "$(bash "$H" process "$T/r.heic")" $'NEEDSREVIEW\nCouldn\'t read the date.\nEND'
resp '{"is_receipt":false,"multiple_receipts":false,"business":"","total":"","date":"","items_summary":"","card_last4":""}'
check "not a receipt" "$(bash "$H" process "$T/r.heic")" $'NOTRECEIPT\nEND'
resp '{"is_receipt":true,"multiple_receipts":true,"business":"A","total":"1","date":"2026-01-01","items_summary":"x","card_last4":""}'
check "multiple receipts" "$(bash "$H" process "$T/r.heic" | head -1)" "NEEDSREVIEW"
check "rejected key" "$(FAKE_KEY=sk-wrong bash "$H" process "$T/r.heic" | sed -n 2p)" "Claude error 401: The API key was rejected. Open Settings and paste a new key."
check "no key saved" "$(FAKE_KEY= bash "$H" process "$T/r.heic" | head -1)" "ERROR"
echo '{"error":{"message":"Your credit balance is too low"}}' > "$T/resp.json"
check "out of credit" "$(FAKE_CODE=400 bash "$H" process "$T/r.heic" | sed -n 2p)" "Claude error 400: Your credit balance is too low"

touch "$T/marker"; sleep 1.1
printf 'x' > "$T/dl/IMG_1.HEIC"; printf 'x' > "$T/dl/notes.pdf"; printf 'x' > "$T/dl/.hidden.jpg"
check "scan waits for files to settle" "$(bash "$H" scan "$T/marker")" ""
sleep 2.1
check "scan finds new images only" "$(bash "$H" scan "$T/marker")" "$T/dl/IMG_1.HEIC"
check "move" "$(bash "$H" move "$T/dl/IMG_1.HEIC" "$T/out/2026/11" '2026-11-23 Home Depot $42.18')" "$T/out/2026/11/2026-11-23 Home Depot \$42.18.heic"
printf 'x' > "$T/dl/b.heic"
check "move never overwrites" "$(bash "$H" move "$T/dl/b.heic" "$T/out/2026/11" '2026-11-23 Home Depot $42.18')" "$T/out/2026/11/2026-11-23 Home Depot \$42.18 (2).heic"
exit $fail
