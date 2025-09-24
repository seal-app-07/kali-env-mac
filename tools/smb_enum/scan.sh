#!/usr/bin/env bash
# smb_enum.sh - SMB enumeration (smbclient + enum4linux)
# Console keeps colors; log is plain (ANSI stripped).
set -euo pipefail
IFS=$'\n\t'

TARGET=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/smb_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> [-o outdir]
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    -o|--out) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done
[ -n "$TARGET" ] || usage
command -v smbclient >/dev/null 2>&1 || { echo "[ERROR] smbclient not found"; exit 2; }

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

echo "=== smb_enum.sh ==="
echo "Target: $TARGET"
echo "Outdir: $OUTDIR"
echo "--- start: $(date) ---"

run_cmd() {
  echo ""
  echo "[*] Running: $*"
  echo ""
  sh -c "$@"
}

# Share list (anonymous)
CMD="smbclient -L '//$TARGET' -N"
# 画面にも出しつつ、個別ファイルにも保存しておく
run_cmd "$CMD" | tee "${OUTDIR}/smb_shares.txt" >/dev/null 2>&1 || \
  echo "[WARN] smbclient list failed (output may be in ${OUTDIR}/smb_shares.txt)"

# enum4linux (if available)
if command -v enum4linux >/dev/null 2>&1; then
  CMD="enum4linux -a $TARGET"
  run_cmd "$CMD" | tee "${OUTDIR}/enum4linux.txt" >/dev/null 2>&1 || \
    echo "[WARN] enum4linux failed (output may be in ${OUTDIR}/enum4linux.txt)"
else
  echo "[WARN] enum4linux not installed; skipping"
fi

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"
