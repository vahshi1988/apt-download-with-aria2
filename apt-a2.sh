#!/usr/bin/env bash
# apt-a2 — Download apt packages via aria2 (using aria2-dl.sh) and install via apt
#
# Usage:
#   apt-a2 install <pkg...>        Install packages
#   apt-a2 reinstall <pkg...>      Reinstall packages
#   apt-a2 upgrade                 Upgrade packages
#   apt-a2 full-upgrade            Dist-upgrade packages
#   apt-a2 --dry-run <command...>  Preview files to be downloaded
#   apt-a2 <any other command>     Pass through to standard apt (update, remove, search, ...)
#
# Environment Variables:
#   A2DL      Path to aria2-dl.sh (default: same directory as this script)
#   A2_CONN   Connections per package (default: 16)

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
  *) (( DRY )) && { echo "This command does not download packages."; exit 0; }
     (( EUID == 0 )) && exec apt "$@" || exec sudo apt "$@" ;;
esac

# Root privileges required for package management
if (( ! DRY && EUID != 0 )); then exec sudo A2DL="$A2DL" A2_CONN="$A2_CONN" "$SELF" "$@"; fi

[[ -x "$A2DL" ]] || { echo "Error: aria2-dl.sh not found: $A2DL" >&2; exit 1; }

# Map commands to apt-get equivalent to retrieve download URLs
rest=("${@:2}")
case "$cmd" in
  reinstall)    getargs=(install --reinstall "${rest[@]}") ;;
  full-upgrade) getargs=(dist-upgrade "${rest[@]}") ;;
  *)            getargs=("$cmd" "${rest[@]}") ;;
esac

if ! uris=$(apt-get -qq --print-uris "${getargs[@]}" 2>/dev/null); then
  # Fallback to standard apt to display official error messages
  (( DRY )) && { apt-get -qq --print-uris "${getargs[@]}"; exit 1; }
  exec apt "$@"
fi

LIST=$(mktemp)
FILES=()
total=0
# Line format: 'URL' FILENAME SIZE HASH
while read -r url file size _; do
  [[ "$url" == \'* ]] || continue
  url=${url#\'}; url=${url%\'}
  # Skip already fully cached archives
  if [[ -f "$ARCHIVES/$file" ]] && [[ $(stat -c%s "$ARCHIVES/$file") == "$size" ]]; then continue; fi
  printf '%s\n  out=%s\n' "$url" "$file" >> "$LIST"
  FILES+=("$file")
  total=$(( total + size ))
done <<<"$uris"

if (( ${#FILES[@]} == 0 )); then
  rm -f "$LIST"
  (( DRY )) && { echo "Nothing to download."; exit 0; }
  exec apt "$@"
fi

human=$(numfmt --to=iec --suffix=B "$total")

if (( DRY )); then
  echo "${#FILES[@]} files, total $human:"
  grep -v '^  ' "$LIST"
  rm -f "$LIST"
  exit 0
fi

echo "Downloading ${#FILES[@]} packages ($human) via aria2..."
"$A2DL" -d "$PARTIAL" -x "$A2_CONN" -i "$LIST" \
  || echo "Warning: some packages failed to download via aria2; apt will fetch remaining packages." >&2
rm -f "$LIST"

# Move fully completed packages (no remaining .aria2 control file) to apt archives cache
for f in "${FILES[@]}"; do
  if [[ -f "$PARTIAL/$f" && ! -e "$PARTIAL/$f.aria2" ]]; then
    mv -f "$PARTIAL/$f" "$ARCHIVES/$f"
  fi
done

# Execute apt to verify integrity and install from cache
exec apt "$@"
