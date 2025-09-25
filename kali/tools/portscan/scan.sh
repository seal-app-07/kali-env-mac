#!/usr/bin/env bash
# scan.sh - rustscan -> nmap pipeline
# Console shows original colors; log is color-stripped (plain text).
set -euo pipefail
IFS=$'\n\t'

# ---- Defaults ----
TARGET=""
BATCH=4500
TIMEOUT=5000
ULIMIT=5000
TOP_PORTS=1000
FULL=false
OS_DETECT=false
RUN_SCRIPTS=false

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/scan_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> [--top N] [--batch N] [--timeout ms] [--full] [--os] [--scripts] [-o outdir]
EOF
  exit 1
}

# ---- Parse Args ----
if [ $# -eq 0 ]; then usage; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    --top) TOP_PORTS="$2"; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --full) FULL=true; shift;;
    --os) OS_DETECT=true; shift;;
    --scripts) RUN_SCRIPTS=true; shift;;
    -o|--out) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done
[ -n "$TARGET" ] || { echo "[ERROR] target required"; usage; }

# ---- Tool Checks ----
command -v rustscan >/dev/null 2>&1 || { echo "[ERROR] rustscan not found"; exit 2; }
command -v nmap     >/dev/null 2>&1 || { echo "[ERROR] nmap not found"; exit 2; }

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

echo "=== scan.sh ==="
echo "Script dir: $SCRIPT_DIR"
echo "Target: $TARGET"
echo "Outdir: $OUTDIR"
echo "Batch: $BATCH  Timeout(ms): $TIMEOUT  TopPorts: $TOP_PORTS"
echo "Full: $FULL  OS_detect: $OS_DETECT  Scripts: $RUN_SCRIPTS"
echo "--- start: $(date) ---"

# ---- Helper ----
run_cmd() {
  echo ""
  echo "[*] Running: $*"
  echo ""
  sh -c "$@"
}

# ---- 1) Quick RustScan Top Ports ----
RS_TOP_CMD="rustscan -a ${TARGET} --ulimit ${ULIMIT} -b ${BATCH} -t ${TIMEOUT} \
  -- -sS -sV -Pn -n --top-ports ${TOP_PORTS} -oN ${OUTDIR}/rustscan_top.nmap"
run_cmd "$RS_TOP_CMD" || echo "[WARN] rustscan top exited non-zero (continuing)"

# ---- 2) Parse open ports ----
OPEN_PORTS=$(grep -E "^[0-9]+/tcp" "${OUTDIR}/rustscan_top.nmap" 2>/dev/null \
  | awk '{print $1}' | cut -d'/' -f1 | paste -sd, - || true)

# ---- 3) Full RustScan if none & requested ----
if [ -z "$OPEN_PORTS" ] && [ "$FULL" = true ]; then
  RS_FULL_CMD="rustscan -a ${TARGET} -r 1-65535 -b ${BATCH} -t ${TIMEOUT} --ulimit ${ULIMIT} \
    -- -sS -sV -Pn -n -p- -oN ${OUTDIR}/rustscan_full.nmap"
  run_cmd "$RS_FULL_CMD" || true
  OPEN_PORTS=$(grep -E "^[0-9]+/tcp" "${OUTDIR}/rustscan_full.nmap" 2>/dev/null \
    | awk '{print $1}' | cut -d'/' -f1 | paste -sd, - || true)
fi

if [ -z "$OPEN_PORTS" ]; then
  echo "[INFO] No open ports discovered. Consider increasing timeout or --full."
  echo "--- end: $(date) ---"
  exit 0
fi

echo "[*] Discovered open ports: $OPEN_PORTS"

# ---- 4) nmap detail on discovered ports ----
NMAP_BASE="nmap -Pn -n -p ${OPEN_PORTS} -oN ${OUTDIR}/nmap_services.nmap -sV"
if [ "$RUN_SCRIPTS" = true ]; then
  NMAP_BASE="$NMAP_BASE -sC --script=vuln"
else
  NMAP_BASE="$NMAP_BASE -sC"
fi
if [ "$OS_DETECT" = true ]; then
  NMAP_CMD="sudo ${NMAP_BASE} --osscan-guess -O ${TARGET}"
else
  NMAP_CMD="${NMAP_BASE} ${TARGET}"
fi
run_cmd "$NMAP_CMD"

# ---- 5) Optional full nmap ----
# if [ "$FULL" = true ]; then
#   FULL_NMAP_CMD="nmap -p- -Pn -n -sS -sV -oN ${OUTDIR}/nmap_full.nmap ${TARGET}"
#   [ "$RUN_SCRIPTS" = true ] && FULL_NMAP_CMD="${FULL_NMAP_CMD} -sC --script=vuln"
#   [ "$OS_DETECT" = true ] && FULL_NMAP_CMD="sudo ${FULL_NMAP_CMD}"
#   run_cmd "$FULL_NMAP_CMD"
# fi

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"
