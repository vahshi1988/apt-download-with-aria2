#!/usr/bin/env bash
# apt-a2 — پکیج‌های apt را با aria2 (از طریق aria2-dl.sh) دانلود می‌کند و بعد apt نصبشان می‌کند
#
# استفاده:
#   apt-a2 install <pkg...>        نصب
#   apt-a2 reinstall <pkg...>      نصب مجدد
#   apt-a2 upgrade                 ارتقا
#   apt-a2 full-upgrade            ارتقای کامل (dist-upgrade)
#   apt-a2 --dry-run <دستور...>    فقط لیست فایل‌هایی که دانلود می‌شن رو نشون بده
#   apt-a2 <هر دستور دیگه>         (update, remove, search, ...) مستقیم به apt داده می‌شه
#
# متغیرها:
#   A2DL      مسیر aria2-dl.sh (پیش‌فرض: کنار همین فایل)
#   A2_CONN   تعداد اتصال برای هر فایل (پیش‌فرض: 16)

set -euo pipefail

SELF=$(readlink -f "${BASH_SOURCE[0]}")
A2DL="${A2DL:-$(dirname "$SELF")/aria2-dl.sh}"
A2_CONN="${A2_CONN:-16}"
ARCHIVES=/var/cache/apt/archives
PARTIAL=$ARCHIVES/partial

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$SELF"; exit "${1:-0}"; }

[[ $# -eq 0 || "$1" == -h || "$1" == --help ]] && usage 0

DRY=0
if [[ "$1" == --dry-run ]]; then DRY=1; shift; [[ $# -eq 0 ]] && usage 1; fi

cmd=$1
case "$cmd" in
  install|reinstall|upgrade|full-upgrade|dist-upgrade) ;;
  *) (( DRY )) && { echo "این دستور چیزی دانلود نمی‌کنه."; exit 0; }
     (( EUID == 0 )) && exec apt "$@" || exec sudo apt "$@" ;;
esac

# برای دانلود و نصب دسترسی root لازمه
if (( ! DRY && EUID != 0 )); then exec sudo A2DL="$A2DL" A2_CONN="$A2_CONN" "$SELF" "$@"; fi

[[ -x "$A2DL" ]] || { echo "✘ aria2-dl.sh پیدا نشد: $A2DL" >&2; exit 1; }

# معادل apt-get برای گرفتن لیست لینک‌ها
rest=("${@:2}")
case "$cmd" in
  reinstall)    getargs=(install --reinstall "${rest[@]}") ;;
  full-upgrade) getargs=(dist-upgrade "${rest[@]}") ;;
  *)            getargs=("$cmd" "${rest[@]}") ;;
esac

if ! uris=$(apt-get -qq --print-uris "${getargs[@]}" 2>/dev/null); then
  # خطا (مثلاً پکیج پیدا نشد) — بذار خود apt پیغام درست رو نشون بده
  (( DRY )) && { apt-get -qq --print-uris "${getargs[@]}"; exit 1; }
  exec apt "$@"
fi

LIST=$(mktemp)
FILES=()
total=0
# فرمت هر خط: 'URL' FILENAME SIZE HASH
while read -r url file size _; do
  [[ "$url" == \'* ]] || continue
  url=${url#\'}; url=${url%\'}
  # اگه قبلاً کامل توی کش هست، رد شو
  if [[ -f "$ARCHIVES/$file" ]] && [[ $(stat -c%s "$ARCHIVES/$file") == "$size" ]]; then continue; fi
  printf '%s\n  out=%s\n' "$url" "$file" >> "$LIST"
  FILES+=("$file")
  total=$(( total + size ))
done <<<"$uris"

if (( ${#FILES[@]} == 0 )); then
  rm -f "$LIST"
  (( DRY )) && { echo "چیزی برای دانلود نیست."; exit 0; }
  exec apt "$@"
fi

human=$(numfmt --to=iec --suffix=B "$total")

if (( DRY )); then
  echo "${#FILES[@]} فایل، مجموعاً $human:"
  grep -v '^  ' "$LIST"
  rm -f "$LIST"
  exit 0
fi

echo "⬇  ${#FILES[@]} پکیج ($human) با aria2 دانلود می‌شه..."
"$A2DL" -d "$PARTIAL" -x "$A2_CONN" -i "$LIST" \
  || echo "⚠  بعضی پکیج‌ها با aria2 دانلود نشدن؛ apt خودش بقیه رو می‌گیره." >&2
rm -f "$LIST"

# فقط فایل‌هایی که کامل دانلود شدن (فایل کنترلی .aria2 ندارن) رو به کش apt منتقل کن
for f in "${FILES[@]}"; do
  if [[ -f "$PARTIAL/$f" && ! -e "$PARTIAL/$f.aria2" ]]; then
    mv -f "$PARTIAL/$f" "$ARCHIVES/$f"
  fi
done

# apt هش فایل‌ها رو خودش چک می‌کنه و از کش نصب می‌کنه
exec apt "$@"
