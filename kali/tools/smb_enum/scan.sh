#!/usr/bin/env bash
# scan.sh - SMB enumeration (smbclient + enum4linux / enum4linux-ng)
# - Every executed command is logged as a single, copy-pastable line
# - Console keeps colors; log file strips ANSI
# - Anonymous (--anon), guest/anonymous empty password attempts (--try-guest)
# - Optional creds, port, timeout; non-intrusive (list only)
set -euo pipefail
IFS=$'\n\t'

VERSION="2025-09-26-smb-slim"

TARGET=""
OUTDIR=""
PORT="445"           # default TCP port for smbclient (139 も可)
TIMEOUT_SEC="20"     # per-command timeout seconds
TRY_GUEST=false
ANON=true            # default is anonymous (-N). Use --no-anon to disable.
CREDS=""             # "user:pass" (or "user:%" for empty password)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/smb_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> [options]

Required:
  -t, --target HOST         Target host or IP

Options:
  -o, --out DIR             Output directory (default: auto)
      --port N              SMB TCP port (default: 445)
      --timeout SEC         Per-command timeout seconds (default: ${TIMEOUT_SEC})
      --creds user:pass     Credentials (use 'user:%' for empty password)
      --anon / --no-anon    Enable/disable smbclient -N anonymous try (default: --anon)
      --try-guest           Additionally try 'guest' and 'anonymous' with empty password
  -h, --help                Show this help

Examples:
  $0 -t 10.10.10.5
  $0 -t 10.10.10.5 --port 139 --timeout 15
  $0 -t 10.10.10.5 --creds alice:Passw0rd
  $0 -t 10.10.10.5 --no-anon --try-guest
EOF
  exit 1
}

# Parse args
[ $# -gt 0 ] || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    -o|--out) OUTDIR="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --timeout) TIMEOUT_SEC="$2"; shift 2;;
    --creds) CREDS="$2"; shift 2;;
    --anon) ANON=true; shift 1;;
    --no-anon) ANON=false; shift 1;;
    --try-guest) TRY_GUEST=true; shift 1;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done

: "${TARGET:?"Missing -t/--target"}"

# Binaries
command -v smbclient >/dev/null || { echo "[ERROR] smbclient not found"; exit 2; }
ENUM4LINUX_BIN="$(command -v enum4linux || true)"
E4L_NG_BIN="$(command -v enum4linux-ng || true)"
TIMEOUT_BIN="$(command -v timeout || true)"
NMBLOOKUP_BIN="$(command -v nmblookup || true)"

mkdir -p "$OUTDIR"
LOG="$OUTDIR/run.log"

# Console color OK / Log strip ANSI
if sed --version >/dev/null 2>&1; then
  exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
else
  exec > >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
fi

# Log-and-run helpers
print_cmd() {
  # print exactly what will run, as one copy-pastable line
  printf '\e[1;34m[*] CMD:\e[0m %s\n' "$1"
}

run_sh() {
  local cmd="$1"
  print_cmd "$cmd"
  # bash -o pipefail preserves failing exit status in pipelines
  bash -o pipefail -c "$cmd"
}

with_timeout() {
  local secs="$1"; shift
  local inner="$*"
  if [ -n "$TIMEOUT_BIN" ]; then
    echo "timeout -k 5s ${secs}s ${inner}"
  else
    # no timeout available; just return inner
    echo "${inner}"
  fi
}

echo "=== scan.sh ($VERSION) ==="
echo "Target: $TARGET"
echo "Outdir: $OUTDIR"
echo "Port: $PORT   Timeout: ${TIMEOUT_SEC}s"
if [ -n "$CREDS" ]; then echo "Creds: (provided)"; else echo "Creds: (none)"; fi
echo "Anon: $ANON   Try-guest: $TRY_GUEST"
echo "--- start: $(date) ---"

# 0) nmblookup (if available): NetBIOS quick info
if [ -n "$NMBLOOKUP_BIN" ]; then
  cmd="$(with_timeout "$TIMEOUT_SEC" "$NMBLOOKUP_BIN -A '$TARGET'")"
  run_sh "$cmd" |& tee "$OUTDIR/nmblookup.txt" >/dev/null
else
  echo "[WARN] nmblookup not found; skipping NetBIOS probe."
fi

# Build smbclient base (common flags):
#  -p PORT : TCP port
#  -m SMB3 : prefer modern dialects; adjust if必要 (e.g., SMB2/NT1)
SMB_BASE="-p ${PORT} -m SMB3"

# 1) Share listing (anonymous / creds / guest order)
#    ※ すべて“実行コマンドが一行でログ”されます

# 1-1) creds provided
if [ -n "$CREDS" ]; then
  # CREDS is "user:pass" (empty pass is 'user:%')
  user="${CREDS%%:*}"
  pass="${CREDS#*:}"
  cmd="$(with_timeout "$TIMEOUT_SEC" "smbclient -L '//$TARGET' ${SMB_BASE} -U '${user}%${pass}'")"
  run_sh "$cmd" |& tee "$OUTDIR/smb_shares_creds.txt" >/dev/null || \
    echo "[WARN] smbclient list with creds failed."
fi

# 1-2) anonymous (-N)
if [ "$ANON" = true ]; then
  cmd="$(with_timeout "$TIMEOUT_SEC" "smbclient -L '//$TARGET' ${SMB_BASE} -N")"
  run_sh "$cmd" |& tee "$OUTDIR/smb_shares_anon.txt" >/dev/null || \
    echo "[WARN] smbclient list (anon) failed."
fi

# 1-3) try guest/anonymous empty password
if [ "$TRY_GUEST" = true ]; then
  for u in guest anonymous; do
    cmd="$(with_timeout "$TIMEOUT_SEC" "smbclient -L '//$TARGET' ${SMB_BASE} -U '${u}%'")"
    run_sh "$cmd" |& tee "$OUTDIR/smb_shares_${u}.txt" >/dev/null || \
      echo "[WARN] smbclient list (${u}%) failed."
  done
fi

# 2) enum4linux / enum4linux-ng
if [ -n "$ENUM4LINUX_BIN" ]; then
  cmd="$(with_timeout "$(( TIMEOUT_SEC * 4 ))" "$ENUM4LINUX_BIN -a '$TARGET'")"
  run_sh "$cmd" |& tee "$OUTDIR/enum4linux.txt" >/dev/null || \
    echo "[WARN] enum4linux failed."
elif [ -n "$E4L_NG_BIN" ]; then
  # enum4linux-ng: YAML + text 両方残す
  cmd_yaml="$(with_timeout "$(( TIMEOUT_SEC * 4 ))" "$E4L_NG_BIN -A '$TARGET' -oY")"
  run_sh "$cmd_yaml" |& tee "$OUTDIR/enum4linux-ng.yaml" >/dev/null || \
    echo "[WARN] enum4linux-ng (YAML) failed."
  cmd_txt="$(with_timeout "$(( TIMEOUT_SEC * 4 ))" "$E4L_NG_BIN -A '$TARGET'")"
  run_sh "$cmd_txt" |& tee "$OUTDIR/enum4linux-ng.txt" >/dev/null || \
    echo "[WARN] enum4linux-ng (text) failed."
else
  echo "[WARN] neither enum4linux nor enum4linux-ng found; skipping."
fi

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"