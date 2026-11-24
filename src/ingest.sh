#!/bin/bash
# Receipt Ingester helper. Called by the app; uses only tools built into macOS.
#
#   ingest.sh scan <marker-file>
#       Prints new, fully-arrived image files in ~/Downloads (one per line).
#   ingest.sh process <image-file>
#       Reads the receipt with Claude and prints one of:
#         OK / business / cost-in-cents / YYYY-MM-DD / items summary / card last 4 / END
#         NOTRECEIPT / END
#         NEEDSREVIEW / reason / END
#         ERROR / message / END
#   ingest.sh move <file> <destination-folder> <new-name-without-extension>
#       Moves the file, never overwriting, and prints the final path.

set -u
# RI_STUB_PATH is only used by the test suite.
export PATH="${RI_STUB_PATH:+$RI_STUB_PATH:}/usr/bin:/bin:/usr/sbin:/sbin"

KC_SERVICE="Receipt Ingester API Key"
DOMAIN="com.receipt-ingester"
DOWNLOADS="${RI_DOWNLOADS:-$HOME/Downloads}"
API_URL="https://api.anthropic.com/v1/messages"

model() {
  local m
  m=$(defaults read "$DOMAIN" Model 2>/dev/null)
  [ -n "$m" ] && echo "$m" || echo "claude-haiku-5-5"
}

# One line, no tabs/newlines, trimmed.
clean() { printf '%s' "$1" | tr '\t\r\n' '   ' | sed -e 's/^ *//' -e 's/ *$//' -e 's/  */ /g'; }

say() { for line in "$@"; do printf '%s\n' "$line"; done; echo END; }

PROMPT='You are reading a photo of a purchase receipt or invoice for a personal expense spreadsheet. Call record_receipt with what you find. business: the store or company name the way a person would write it (for example Home Depot, not THE HOME DEPOT #1234). total: the final amount paid including tax and tip, digits only, like 42.18. date: the purchase date as YYYY-MM-DD; US receipts write month/day/year. items_summary: a short plain-English summary of what was bought, under 12 words, for example Lumber, deck screws, wood stain; for a service invoice, describe the work. card_last4: the last 4 digits of the payment card if they are printed (for example from ************4417 or ending in 4417), otherwise an empty string. Leave a field empty if you cannot read it confidently; never guess a total or a date. Set is_receipt to false if the photo is not a receipt or invoice. Set multiple_receipts to true if the photo shows more than one separate receipt.'

TOOL='{"name":"record_receipt","description":"Record the details of one receipt.","input_schema":{"type":"object","properties":{"is_receipt":{"type":"boolean"},"multiple_receipts":{"type":"boolean"},"business":{"type":"string"},"total":{"type":"string"},"date":{"type":"string"},"items_summary":{"type":"string"},"card_last4":{"type":"string"}},"required":["is_receipt","multiple_receipts","business","total","date","items_summary","card_last4"]}}'

scan() {
  local marker="$1" f s1 s2
  [ -e "$marker" ] || return 0
  find "$DOWNLOADS" -maxdepth 1 -type f ! -name '.*' -cnewer "$marker" \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.heif' \) \
    2>/dev/null | while IFS= read -r f; do
      # Only hand over files that have finished arriving.
      s1=$(stat -f %z "$f" 2>/dev/null) || continue
      sleep 1
      s2=$(stat -f %z "$f" 2>/dev/null) || continue
      if [ "$s1" = "$s2" ] && [ "$s1" -gt 0 ]; then printf '%s\n' "$f"; fi
    done
}

process() {
  local src="$1" key code attempt msg idx i
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/receipt-ingester.XXXXXX") || { say ERROR "Couldn't create a temporary folder."; return; }
  trap 'rm -rf "$tmp"' EXIT   # tmp is global on purpose so the EXIT trap can see it

  # Convert HEIC/PNG/large JPEG to a modest JPEG (cheaper, and within API limits).
  if ! sips -s format jpeg -s formatOptions 85 -Z 1568 "$src" --out "$tmp/r.jpg" >/dev/null 2>&1 || [ ! -s "$tmp/r.jpg" ]; then
    say ERROR "Couldn't open this photo."; return
  fi

  key=$(security find-generic-password -s "$KC_SERVICE" -w 2>/dev/null)
  if [ -z "$key" ]; then say ERROR "No Claude API key is saved. Open Receipt Ingester and choose Settings to add it."; return; fi

  {
    printf '{"model":"%s","max_tokens":600,"tools":[%s],"tool_choice":{"type":"tool","name":"record_receipt"},' "$(model)" "$TOOL"
    printf '"messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"'
    base64 < "$tmp/r.jpg" | tr -d '\n\r'
    printf '"}},{"type":"text","text":"%s"}]}]}' "$PROMPT"
  } > "$tmp/req.json"

  code=000
  for attempt in 1 2 3; do
    rm -f "$tmp/resp.json"
    # The key is fed through stdin (printf is a shell builtin), so it never appears in the process list.
    code=$(printf 'header = "x-api-key: %s"\n' "$key" | curl -sS --config - \
      -o "$tmp/resp.json" -w '%{http_code}' --max-time 120 \
      -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
      --data-binary @"$tmp/req.json" "$API_URL" 2>/dev/null)
    case "$code" in
      200) break ;;
      000|408|429|500|502|503|504|529) [ "$attempt" -lt 3 ] && sleep $((attempt * 5)) ;;
      *) break ;;
    esac
  done

  get() { plutil -extract "$1" raw -o - "$tmp/resp.json" 2>/dev/null; }

  if [ "$code" != 200 ]; then
    if [ "$code" = 000 ]; then say ERROR "Couldn't reach Claude. Check the internet connection."; return; fi
    msg=$(clean "$(get error.message)")
    case "$code" in
      401) msg="The API key was rejected. Open Settings and paste a new key." ;;
    esac
    say ERROR "Claude error $code: ${msg:-unknown error}"; return
  fi

  idx=""
  for i in 0 1 2 3; do
    if [ "$(get content.$i.type)" = "tool_use" ]; then idx=$i; break; fi
  done
  if [ -z "$idx" ]; then say ERROR "Claude's answer couldn't be read."; return; fi

  local p="content.$idx.input" is_receipt multiple business total date notes last4 cents
  is_receipt=$(get "$p.is_receipt")
  multiple=$(get "$p.multiple_receipts")
  business=$(clean "$(get "$p.business")")
  total=$(clean "$(get "$p.total")" | tr -d '$, ')
  date=$(clean "$(get "$p.date")")
  notes=$(clean "$(get "$p.items_summary")")
  last4=$(clean "$(get "$p.card_last4")" | tr -cd '0-9')

  case "$is_receipt" in false|0|NO) say NOTRECEIPT; return ;; esac
  case "$multiple" in true|1|YES) say NEEDSREVIEW "This photo seems to show more than one receipt. Please photograph them one at a time."; return ;; esac

  if [ -z "$business" ]; then say NEEDSREVIEW "Couldn't read the store name."; return; fi
  if ! printf '%s' "$total" | grep -Eq '^[0-9]+(\.[0-9]{1,2})?$'; then say NEEDSREVIEW "Couldn't read the total."; return; fi
  if ! printf '%s' "$date" | grep -Eq '^(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then say NEEDSREVIEW "Couldn't read the date."; return; fi
  [ ${#last4} -eq 4 ] || last4=""

  cents=$(printf '%s' "$total" | awk '{ printf "%d", ($1 * 100) + 0.5 }')
  say OK "$business" "$cents" "$date" "$notes" "$last4"
}

move() {
  local src="$1" dir="$2" base="$3" ext safe dest n=2
  ext=$(printf '%s' "${src##*.}" | tr 'A-Z' 'a-z')
  mkdir -p "$dir" || exit 1
  safe=$(printf '%s' "$base" | tr '/:' '--' | tr -d '\000-\037' | cut -c1-90)
  [ -n "$safe" ] || safe="Receipt"
  dest="$dir/$safe.$ext"
  while [ -e "$dest" ]; do dest="$dir/$safe ($n).$ext"; n=$((n + 1)); done
  mv "$src" "$dest" && printf '%s\n' "$dest"
}

case "${1:-}" in
  scan) scan "${2:?marker}" ;;
  process) process "${2:?file}" ;;
  move) move "${2:?file}" "${3:?folder}" "${4:?name}" ;;
  *) echo "usage: ingest.sh scan|process|move ..." >&2; exit 2 ;;
esac
