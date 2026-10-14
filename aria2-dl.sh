#!/usr/bin/env bash
# aria2-dl.sh — Multi-connection download accelerator wrapper for aria2
#
# Usage:
#   aria2-dl.sh <URL> [URL ...]            Download URLs directly
#   aria2-dl.sh                             Prompt for URL interactively
#   aria2-dl.sh -i links.txt                Download list of URLs from file
#   aria2-dl.sh -p <URL>                    Print equivalent aria2c command without executing
#   aria2-dl.sh -r <URL>                    Send URL to running aria2 RPC daemon
#
# Options:
#   -d DIR     Download directory (default: ~/Downloads)
#   -o NAME    Output filename (single URL only)
#   -x N       Max connections per server (default: 16)
#   -i FILE    File containing URLs (one per line)
#   -R URL     Referer header
#   -c FILE    Cookie file (Netscape format)
#   -H HEADER  Additional HTTP header (can be repeated)
#   -p         Print command only
#   -r         Send to RPC ($ARIA2_RPC or http://localhost:6800/jsonrpc, secret: $ARIA2_SECRET)
#   -h         Show help

set -euo pipefail

DIR="${HOME}/Downloads"
OUT=""
CONN=16
INPUT_FILE=""
REFERER=""
COOKIE=""
HEADERS=()
PRINT_ONLY=0
RPC=0
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit "${1:-0}"; }

while getopts ":d:o:x:i:R:c:H:prh" opt; do
  case "$opt" in
    d) DIR="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    x) CONN="$OPTARG" ;;
    i) INPUT_FILE="$OPTARG" ;;
    R) REFERER="$OPTARG" ;;
    c) COOKIE="$OPTARG" ;;
    H) HEADERS+=("$OPTARG") ;;
    p) PRINT_ONLY=1 ;;
    r) RPC=1 ;;
    h) usage 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage 1 ;;
  esac
done
shift $((OPTIND - 1))

URLS=("$@")

# If no URLs provided and no input file, prompt user
if [[ ${#URLS[@]} -eq 0 && -z "$INPUT_FILE" ]]; then
  read -rp "Enter download URL: " link
  [[ -z "$link" ]] && { echo "No URL provided." >&2; exit 1; }
  URLS=("$link")
fi

(( CONN > 16 )) && CONN=16   # aria2 allows max 16 connections per server

die() { echo "Error: $*" >&2; exit 1; }

(( ${#URLS[@]} > 1 )) && [[ -n "$OUT" ]] && die "-o can only be used with a single URL."

# ---------- RPC Mode: send to running aria2 daemon ----------
if (( RPC )); then
  command -v curl >/dev/null || { echo "curl is required for RPC mode." >&2; exit 1; }
  RPC_URL="${ARIA2_RPC:-http://localhost:6800/jsonrpc}"
  [[ -n "$INPUT_FILE" ]] && mapfile -t -O "${#URLS[@]}" URLS < <(grep -vE '^\s*(#|$)' "$INPUT_FILE")
  json_esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }
  for u in "${URLS[@]}"; do
    opts="\"dir\":\"$(json_esc "$DIR")\",\"split\":\"$CONN\",\"max-connection-per-server\":\"$CONN\",\"min-split-size\":\"1M\",\"continue\":\"true\""
    [[ -n "$OUT" ]] && opts+=",\"out\":\"$(json_esc "$OUT")\""
    [[ -n "$REFERER" ]] && opts+=",\"referer\":\"$(json_esc "$REFERER")\""
    params="[\"$(json_esc "$u")\"],{${opts}}"
    [[ -n "${ARIA2_SECRET:-}" ]] && params="\"token:${ARIA2_SECRET}\",${params}"
    resp=$(curl -fsS "$RPC_URL" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":\"a2\",\"method\":\"aria2.addUri\",\"params\":[${params}]}") \
      || { echo "Connection to RPC at $RPC_URL failed." >&2; exit 1; }
    echo "Added: $u -> $resp"
  done
  exit 0
fi

# ---------- Build aria2c command ----------
CMD=(aria2c
  --continue=true
  --max-connection-per-server="$CONN"
  --split="$CONN"
  --min-split-size=1M
  --max-tries=10
  --retry-wait=5
  --timeout=60
  --file-allocation=none
  --auto-file-renaming=false
  --summary-interval=0
  --console-log-level=warn
  --user-agent="$UA"
  --dir="$DIR"
)
[[ -n "$OUT" ]]     && CMD+=(--out="$OUT")
[[ -n "$REFERER" ]] && CMD+=(--referer="$REFERER")
[[ -n "$COOKIE" ]]  && CMD+=(--load-cookies="$COOKIE")
for h in "${HEADERS[@]}"; do CMD+=(--header="$h"); done
[[ -n "$INPUT_FILE" ]] && CMD+=(--input-file="$INPUT_FILE")
# Without --force-sequential, multiple URLs are treated as mirrors of one file
(( ${#URLS[@]} > 1 )) && CMD+=(--force-sequential=true)
CMD+=("${URLS[@]}")

if (( PRINT_ONLY )); then
  printf '%q ' "${CMD[@]}"; echo
  exit 0
fi

command -v aria2c >/dev/null || {
  echo "aria2c is not installed. Install via: sudo apt install aria2 (or: sudo pacman -S aria2 / sudo dnf install aria2)" >&2
  exit 1
}

mkdir -p "$DIR"
echo "Downloading with $CONN connections to: $DIR"
exec "${CMD[@]}"
