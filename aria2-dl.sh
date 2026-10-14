#!/usr/bin/env bash
# aria2-dl.sh — لینک دانلود را می‌گیرد و با aria2 (چند اتصاله) دانلود می‌کند
#
# استفاده:
#   aria2-dl.sh <URL> [URL ...]            دانلود مستقیم
#   aria2-dl.sh                             لینک را از ورودی می‌پرسد
#   aria2-dl.sh -i links.txt                دانلود لیست لینک‌ها از فایل
#   aria2-dl.sh -p <URL>                    فقط دستور aria2c را چاپ کن (اجرا نکن)
#   aria2-dl.sh -r <URL>                    ارسال لینک به aria2 در حال اجرا (RPC)
#
# گزینه‌ها:
#   -d DIR     پوشه ذخیره (پیش‌فرض: ~/Downloads)
#   -o NAME    نام فایل خروجی (فقط برای یک لینک)
#   -x N       تعداد اتصال‌ها (پیش‌فرض: 16)
#   -i FILE    فایل حاوی لینک‌ها (هر خط یک لینک)
#   -R URL     Referer
#   -c FILE    فایل کوکی (فرمت Netscape)
#   -H HEADER  هدر اضافه، مثلا: -H "Authorization: Bearer xxx" (قابل تکرار)
#   -p         فقط دستور را چاپ کن
#   -r         ارسال به RPC (آدرس: $ARIA2_RPC یا http://localhost:6800/jsonrpc ، توکن: $ARIA2_SECRET)
#   -h         راهنما

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
    :) echo "گزینه -$OPTARG نیاز به مقدار دارد" >&2; usage 1 ;;
    \?) echo "گزینه نامعتبر: -$OPTARG" >&2; usage 1 ;;
  esac
done
shift $((OPTIND - 1))

URLS=("$@")

# اگر لینکی داده نشده و فایل ورودی هم نیست، از کاربر بپرس
if [[ ${#URLS[@]} -eq 0 && -z "$INPUT_FILE" ]]; then
  read -rp "لینک دانلود را وارد کنید: " link
  [[ -z "$link" ]] && { echo "لینکی وارد نشد." >&2; exit 1; }
  URLS=("$link")
fi

(( CONN > 16 )) && CONN=16   # aria2 حداکثر 16 اتصال به هر سرور را قبول می‌کند

die() { echo "✘ $*" >&2; exit 1; }

(( ${#URLS[@]} > 1 )) && [[ -n "$OUT" ]] && die "-o فقط با یک لینک قابل استفاده است."

# ---------- حالت RPC: ارسال به aria2 در حال اجرا ----------
if (( RPC )); then
  command -v curl >/dev/null || { echo "curl نصب نیست." >&2; exit 1; }
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
      || { echo "اتصال به RPC در $RPC_URL ناموفق بود." >&2; exit 1; }
    echo "✔ اضافه شد: $u  →  $resp"
  done
  exit 0
fi

# ---------- ساخت دستور aria2c ----------
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
# بدون -Z، aria2 چند لینک را mirror یک فایل حساب می‌کند؛ با -Z هر لینک یک دانلود جداست
(( ${#URLS[@]} > 1 )) && CMD+=(--force-sequential=true)
CMD+=("${URLS[@]}")

if (( PRINT_ONLY )); then
  printf '%q ' "${CMD[@]}"; echo
  exit 0
fi

command -v aria2c >/dev/null || {
  echo "aria2c نصب نیست. نصب: sudo apt install aria2  (یا: sudo pacman -S aria2 / sudo dnf install aria2)" >&2
  exit 1
}

mkdir -p "$DIR"
echo "⬇  دانلود با $CONN اتصال در: $DIR"
exec "${CMD[@]}"
