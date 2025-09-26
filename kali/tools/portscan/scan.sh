#!/usr/bin/env bash
# scan.sh - rustscan -> nmap pipeline (improved)
# - Every executed command is logged as a single, copy-pastable line
# - Non-root: fallback to -sT (no raw sockets) / Root: use -sS
# - Save nmap results in normal, grepable, and XML formats
# - Robust port parsing from rustscan's nmap-normal output
set -euo pipefail
IFS=$'\n\t'

# ---- Defaults ----
TARGET=""
BATCH=4500
TIMEOUT=5000           # rustscan per-host timeout (ms)
ULIMIT=5000
TOP_PORTS=1000
FULL=false             # --full: run rustscan full range if top-ports finds none
OS_DETECT=false        # --os: nmap -O (needs sudo/root)
RUN_SCRIPTS=false      # --scripts: add -sC and --script=vuln
NMAP_TIMEOUT=""        # optional seconds; if set and 'timeout' exists, we prefix

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/scan_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> [--top N] [--batch N] [--timeout ms] [--full] [--os] [--scripts] [--nmap-timeout sec] [-o outdir]

Options:
  -t, --target           Target (IP/hostname)
      --top N            rustscan -> nmap top ports (default: ${TOP_PORTS})
      --batch N          rustscan batch size (default: ${BATCH})
      --timeout ms       rustscan per-host timeout in ms (default: ${TIMEOUT})
      --full             If no ports found in top scan, run full (1-65535)
      --os               nmap OS detection (-O) [sudo/root recommended]
      --scripts          nmap default scripts (-sC) + vuln category
      --nmap-timeout sec Prefix 'timeout sec' when running nmap (if 'timeout' exists)
  -o, --out DIR          Output directory (default: ${OUTDIR_DEFAULT})
  -h, --help             Show this help
EOF
  exit 1
}

# ---- Parse Args ----
[ $# -gt 0 ] || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    --top) TOP_PORTS="$2"; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --full) FULL=true; shift;;
    --os) OS_DETECT=true; shift;;
    --scripts) RUN_SCRIPTS=true; shift;;
    --nmap-timeout) NMAP_TIMEOUT="$2"; shift 2;;
    -o|--out) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done
[ -n "$TARGET" ] || { echo "[ERROR] target required"; usage; }

# ---- Tool Checks ----
command -v rustscan >/dev/null 2>&1 || { echo "[ERROR] rustscan not found"; exit 2; }
command -v nmap     >/dev/null 2>&1 || { echo "[ERROR] nmap not found"; exit 2; }
TIMEOUT_BIN="$(command -v timeout || true)"

# ---- Outdir & Logging ----
mkdir -p "$OUTDIR"
LOG="$OUTDIR/run.log"

# Console: color OK / Log: strip ANSI
if sed --version >/dev/null 2>&1; then  # GNU sed
  exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
else                                    # BSD/macOS sed
  exec > >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -E  's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
fi

# ---- Log helpers ----
print_cmd() { printf '\e[1;34m[*] CMD:\e[0m %s\n' "$1"; }
run_sh() {
  local line="$1"
  print_cmd "$line"
  bash -o pipefail -c "$line"
}
with_timeout() {
  local inner="$1"
  if [ -n "$NMAP_TIMEOUT" ] && [ -n "$TIMEOUT_BIN" ]; then
    echo "timeout -k 5s ${NMAP_TIMEOUT}s ${inner}"
  else
    echo "${inner}"
  fi
}

echo "=== scan.sh ==="
echo "Script dir: $SCRIPT_DIR"
echo "Target: $TARGET"
echo "Outdir: $OUTDIR"
echo "Batch: $BATCH  Timeout(ms): $TIMEOUT  TopPorts: $TOP_PORTS  FullScanOnEmpty: $FULL"
echo "OS_detect: $OS_DETECT  Scripts: $RUN_SCRIPTS  NmapTimeout: ${NMAP_TIMEOUT:-none}"
echo "--- start: $(date) ---"

# ---- 1) Quick RustScan Top Ports ----
RS_TOP="${OUTDIR}/rustscan_top.nmap"
RS_TOP_CMD="rustscan -a '${TARGET}' --ulimit ${ULIMIT} -b ${BATCH} -t ${TIMEOUT} \
  -- -sS -sV -Pn -n --top-ports ${TOP_PORTS} -oN '${RS_TOP}'"
run_sh "$RS_TOP_CMD" || echo "[WARN] rustscan(top) exited non-zero (continuing)"

# ---- 2) Parse open ports from rustscan's nmap-normal output ----
OPEN_PORTS=""
if [ -s "$RS_TOP" ]; then
  # nmap normal: lines like '22/tcp open ssh'
  OPEN_PORTS="$(
    awk '/^[0-9]+\/tcp/ && $2 ~ /open|open\|filtered/ {print $1}' "$RS_TOP" \
    | cut -d/ -f1 | paste -sd, - 2>/dev/null || true
  )"
fi

# ---- 3) Full RustScan if none & requested ----
if [ -z "$OPEN_PORTS" ] && [ "$FULL" = true ]; then
  RS_FULL="${OUTDIR}/rustscan_full.nmap"
  RS_FULL_CMD="rustscan -a '${TARGET}' -r 1-65535 -b ${BATCH} -t ${TIMEOUT} --ulimit ${ULIMIT} \
    -- -sS -sV -Pn -n -p- -oN '${RS_FULL}'"
  run_sh "$RS_FULL_CMD" || true
  if [ -s "$RS_FULL" ]; then
    OPEN_PORTS="$(
      awk '/^[0-9]+\/tcp/ && $2 ~ /open|open\|filtered/ {print $1}' "$RS_FULL" \
      | cut -d/ -f1 | paste -sd, - 2>/dev/null || true
    )"
  fi
fi

if [ -z "$OPEN_PORTS" ]; then
  echo "[INFO] No open ports discovered. Consider increasing --timeout or using --full."
  echo "--- end: $(date) ---"
  exit 0
fi

echo "[*] Discovered open ports: $OPEN_PORTS"

# ---- 4) Build nmap command on discovered ports ----
# Non-root fallback: -sS requires raw sockets; if not root, use -sT
TCP_SCAN="-sS"
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  TCP_SCAN="-sT"
  echo "[INFO] Non-root detected -> using -sT (connect scan). Run as root for -sS."
fi

NMAP_OUT_N="${OUTDIR}/nmap_services.nmap"
NMAP_OUT_G="${OUTDIR}/nmap_services.grep"
NMAP_OUT_X="${OUTDIR}/nmap_services.xml"

NMAP_BASE="nmap -Pn -n -p ${OPEN_PORTS} ${TCP_SCAN} -sV -oN '${NMAP_OUT_N}' -oG '${NMAP_OUT_G}' -oX '${NMAP_OUT_X}'"
if [ "$RUN_SCRIPTS" = true ]; then
  NMAP_BASE="${NMAP_BASE} -sC --script=vuln"
fi
if [ "$OS_DETECT" = true ]; then
  NMAP_BASE="${NMAP_BASE} -O --osscan-guess"
fi
NMAP_CMD="${NMAP_BASE} '${TARGET}'"

# optional 'timeout' wrapper for nmap
NMAP_CMD="$(with_timeout "$NMAP_CMD")"
run_sh "$NMAP_CMD"

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"