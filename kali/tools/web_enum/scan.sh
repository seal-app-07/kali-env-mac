#!/usr/bin/env bash
# scan.sh - web enum (headers via curl, dir enum via gobuster -> ffuf fallback)
# - Logs every executed command as a single, copy-pastable line
# - Proper header dump via curl -D
# - Ports accept "80" or "https:8443"
# - No mini wordlist (always use provided wordlist)
set -euo pipefail
IFS=$'\n\t'

VERSION="2025-09-26-slim2"

# Defaults
WORDLIST="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
THREADS=20
CURL_TIMEOUT=10
GOB_TIMEOUT="30s"         # gobuster per-request
FFUF_THREADS=20
FFUF_DELAY="0.10"         # seconds between requests
FFUF_CODES="200-299,301,302,307,401,403,405,500"
UA="Mozilla/5.0"
HOST_OVERRIDE=""          # e.g. vhost.example
EXTENSIONS=""             # e.g. php,txt,html
INSECURE=false
OUTDIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR_DEFAULT="${SCRIPT_DIR}/web_$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUTDIR_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 -t <target> -p <ports_csv_or_schema_port> [options]

Required:
  -t, --target           Target host or IP (IPv4 or IPv6)
  -p, --ports            Comma separated list. Entry: "80" or "https:8443" etc.

Options:
  --wordlist PATH        (default: $WORDLIST)
  --threads N            gobuster threads (default: $THREADS)
  --curl-timeout SEC     curl max time (default: $CURL_TIMEOUT)
  --gob-timeout DUR      gobuster per-request timeout (e.g. 30s) (default: $GOB_TIMEOUT)
  --ffuf-threads N       ffuf threads (default: $FFUF_THREADS)
  --ffuf-delay SEC       ffuf per-request delay (default: $FFUF_DELAY)
  --ffuf-codes LIST      ffuf match status codes (default: $FFUF_CODES)
  --user-agent STR       UA for curl/ffuf/gobuster (default: "$UA")
  --host NAME            Force Host header (vhost). Applied to all tools.
  --ext csv              Extensions for enum (e.g. php,txt,html)
  --insecure             Skip TLS verification (-k for curl/gobuster/ffuf)
  -o, --out DIR          Output directory (default: auto)
  -h, --help             Show this help

Example:
  $0 -t 10.10.10.5 -p 80,https:8443 --threads 10 --ffuf-delay 0.2 --host site.local --ext php,txt
EOF
  exit 1
}

# Parse args
[ $# -gt 0 ] || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    -p|--ports) PORTS="$2"; shift 2;;
    --wordlist) WORDLIST="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2;;
    --gob-timeout) GOB_TIMEOUT="$2"; shift 2;;
    --ffuf-threads) FFUF_THREADS="$2"; shift 2;;
    --ffuf-delay) FFUF_DELAY="$2"; shift 2;;
    --ffuf-codes) FFUF_CODES="$2"; shift 2;;
    --user-agent) UA="$2"; shift 2;;
    --host) HOST_OVERRIDE="$2"; shift 2;;
    --ext) EXTENSIONS="$2"; shift 2;;
    --insecure) INSECURE=true; shift 1;;
    -o|--out) OUTDIR="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
done

: "${TARGET:?"Missing -t/--target"}"
: "${PORTS:?"Missing -p/--ports"}"

command -v curl >/dev/null || { echo "[ERROR] curl not found"; exit 2; }
GOBUSTER_BIN="$(command -v gobuster || true)"
FFUF_BIN="$(command -v ffuf || true)"

mkdir -p "$OUTDIR"
LOG="$OUTDIR/run.log"

# Logging: console color OK, log with ANSI stripped
if sed --version >/dev/null 2>&1; then
  exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -r 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
else
  exec > >(tee >(sed -u -E 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG")) \
       2> >(tee >(sed -u -E 's/\x1B\[[0-9;]*[ -/]*[@-~]//g' >>"$LOG") >&2)
fi

# Utility: 1行表示＆実行（配列→シェルエスケープ）
run_cmd() {
  local -a cmd=( "$@" )
  local line=""; printf -v line '%q ' "${cmd[@]}"; echo -e "\e[1;34m[*] CMD:\e[0m ${line% }"
  "${cmd[@]}"
}

echo "=== scan.sh ($VERSION) ==="
echo "Target: $TARGET"
echo "Ports: $PORTS"
echo "Outdir: $OUTDIR"
echo "Wordlist: $WORDLIST  Threads: $THREADS"
echo "UA: $UA  Host: ${HOST_OVERRIDE:-none}  Insecure: $INSECURE"
[ -n "$EXTENSIONS" ] && echo "Extensions: $EXTENSIONS"
echo "--- start: $(date) ---"

# Helpers
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
is_ipv6() { [[ "$1" == *:* && "$1" != *"://"* ]]; }

# IPv6は [addr] 形式へ
build_host() {
  local h="$1"
  if is_ipv6 "$h"; then echo "[$h]"; else echo "$h"; fi
}

# Build URL from scheme/host/port
build_url() {
  local scheme="$1" host="$2" port="$3"
  echo "${scheme}://${host}:${port}"
}

# curl/gobuster/ffuf 共通のInsecure/Host/UA組み立て
curl_common=()
[ "$INSECURE" = true ] && curl_common+=(-k)
curl_common+=(-A "$UA")
[ -n "$HOST_OVERRIDE" ] && curl_common+=(-H "Host: $HOST_OVERRIDE")

gob_common=()
[ "$INSECURE" = true ] && gob_common+=(-k)
# gobusterはUA上書き挙動がある版もあるが、-Hは渡す
[ -n "$HOST_OVERRIDE" ] && gob_common+=(-H "Host: $HOST_OVERRIDE")
gob_common+=(-H "User-Agent: $UA")
[ -n "$EXTENSIONS" ] && gob_common+=(-x "$EXTENSIONS")

ffuf_common=()
[ "$INSECURE" = true ] && ffuf_common+=(-k)
ffuf_common+=(-H "User-Agent: $UA")
[ -n "$HOST_OVERRIDE" ] && ffuf_common+=(-H "Host: $HOST_OVERRIDE")
[ -n "$EXTENSIONS" ] && ffuf_common+=(-e ".$EXTENSIONS")

# Validate wordlist existence (無ければディレクトリ列挙スキップ)
if [ ! -f "$WORDLIST" ]; then
  echo "[WARN] Wordlist not found at $WORDLIST; directory enumeration will be skipped."
fi

host_fmt="$(build_host "$TARGET")"
IFS=',' read -r -a PORT_ARR <<< "$PORTS"

for raw in "${PORT_ARR[@]}"; do
  entry="$(echo "$raw" | tr -d '[:space:]')"
  scheme="" ; port=""
  if [[ "$entry" == *:* ]]; then
    scheme="$(lower "${entry%%:*}")"
    port="${entry##*:}"
  else
    port="$entry"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -eq 443 ] 2>/dev/null; then
      scheme="https"
    else
      scheme="http"
    fi
  fi

  if [[ -z "$scheme" || -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
    echo "[WARN] Invalid port entry: '$raw' (parsed scheme='$scheme' port='$port') - skipping"
    continue
  fi

  url="$(build_url "$scheme" "$host_fmt" "$port")"
  echo -e "\e[1;32m=== Processing ${url} ===\e[0m"

  # 1) curl headers
  hdr_file="${OUTDIR}/http_${port}.headers"
  run_cmd curl -sS -I --max-time "$CURL_TIMEOUT" "${curl_common[@]}" "$url" -D "$hdr_file" -o /dev/null \
    || echo "[WARN] curl -I failed for $url"
  [ -s "$hdr_file" ] && echo "[*] headers saved: $hdr_file"

  # 2) directory enum
  if [ -f "$WORDLIST" ]; then
    if [ -n "$GOBUSTER_BIN" ]; then
      gob_out="${OUTDIR}/gobuster_${port}.txt"
      run_cmd "$GOBUSTER_BIN" dir -u "$url" -w "$WORDLIST" -t "$THREADS" -to "$GOB_TIMEOUT" -o "$gob_out" "${gob_common[@]}" \
        || {
          echo "[WARN] gobuster failed (rc=$?). Falling back to ffuf if available."
          if [ -n "$FFUF_BIN" ]; then
            ffuf_out="${OUTDIR}/ffuf_${port}.json"
            # GOB_TIMEOUT like '30s' -> seconds number for ffuf --timeout
            ffuf_timeout="${GOB_TIMEOUT%s}"
            run_cmd "$FFUF_BIN" -u "${url}/FUZZ" -w "$WORDLIST" -t "$FFUF_THREADS" -timeout "$ffuf_timeout" -p "$FFUF_DELAY" \
                               -mc "$FFUF_CODES" -o "$ffuf_out" -of json "${ffuf_common[@]}" \
              || echo "[WARN] ffuf failed (rc=$?)."
          fi
        }
    elif [ -n "$FFUF_BIN" ]; then
      ffuf_out="${OUTDIR}/ffuf_${port}.json"
      ffuf_timeout="${GOB_TIMEOUT%s}"
      run_cmd "$FFUF_BIN" -u "${url}/FUZZ" -w "$WORDLIST" -t "$FFUF_THREADS" -timeout "$ffuf_timeout" -p "$FFUF_DELAY" \
                         -mc "$FFUF_CODES" -o "$ffuf_out" -of json "${ffuf_common[@]}" \
        || echo "[WARN] ffuf failed (rc=$?)."
    else
      echo "[WARN] Neither gobuster nor ffuf found; skipping directory enumeration."
    fi
  else
    echo "[WARN] Wordlist not found; skipping directory enumeration."
  fi

  echo -e "\e[1;32m--- done for ${url} ---\e[0m"
done

echo "--- end: $(date) ---"
echo "[*] Outputs saved in: $OUTDIR"