#!/usr/bin/env bash
# scan.sh - HTTP(S) enumeration (headers + gobuster)
# Console keeps colors; log is plain (ANSI stripped).
set -euo pipefail
IFS=$'\n\t'

TARGET=""
PORTS=""
WORDLIST="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
THREADS=20

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/web_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> -p <ports_csv> [--wordlist path] [--threads N] [-o outdir]
EOF
  exit 1
}

[ $# -gt 0 ] || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    -p|--ports) PORTS="$2"; shift 2;;
    --wordlist) WORDLIST="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    -o|--out) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done
[ -n "$TARGET" ] && [ -n "$PORTS" ] || usage
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl not found"; exit 2; }

mkdir -p "$OUTDIR"
LOG="$OUTDIR/run.log"

# Console: color OK / Log: strip ANSI
if sed --version >/dev/null 2>&1; then
  exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
else
  exec > >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
fi

echo "=== scan.sh ==="
echo "Target: $TARGET"
echo "Ports: $PORTS"
echo "Outdir: $OUTDIR"
echo "Wordlist: $WORDLIST  Threads: $THREADS"
echo "--- start: $(date) ---"

run_cmd() {
  echo ""
  echo "[*] Running: $*"
  echo ""
  sh -c "$@"
}

IFS=',' read -ra PORT_ARR <<< "$PORTS"
for p in "${PORT_ARR[@]}"; do
  scheme="http"; if [ "$p" -eq 443 ] 2>/dev/null; then scheme="https"; fi
  url="${scheme}://${TARGET}:${p}"

  CMD="curl -I --max-time 10 '$url' -o '${OUTDIR}/http_${p}.headers'"
  run_cmd "$CMD" || echo "[WARN] curl headers failed for $url"

  if command -v gobuster >/dev/null 2>&1 && [ -f "$WORDLIST" ]; then
    # gobusterにカラー抑止オプションはないが、ログ側では色は除去される
    CMD="gobuster dir -u '$url' -w '$WORDLIST' -t $THREADS -o '${OUTDIR}/gobuster_${p}.txt' -q"
    run_cmd "$CMD" || echo "[WARN] gobuster failed for $url"
  else
    echo "[WARN] gobuster or wordlist not available; skipping dir enum for $url"
  fi
done

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"
