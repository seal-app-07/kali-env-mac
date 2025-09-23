#!/bin/sh
set -eu

usage() {
  cat <<EOF
Usage: ${0##*/} -T<0-5> [options]

Options:
  -T <0-5>         Nmap timing template
  -t <hosts>       Target hosts directly (comma separated)
  -x <hosts>       Exclude hosts directly (comma separated)
  -f <file>        Target hosts from file
  -e <file>        Exclude hosts from file
  -o <dir>         Output directory (default: ./results/YYYYMMDD)
  -h               Show this help
  -p		   Disable ping
EOF
}

# default values
today=$(date +%Y%m%d%H%M%S)
current=$(cd $(dirname $0);pwd)
outdir="$current/results/${today}"
now=$(date +%Y%m%d_%H%M%S)
targets=""
excludes=""
timing_template=""
logfile="${outdir}/scan_${now}.log"
failed_hosts="${outdir}/failed_${now}.txt"
ping_disable=""

# parse options
while getopts "T:t:x:f:e:o:h:p" opt; do
  case "$opt" in
    T) timing_template="-T${OPTARG}" ;;
    t) targets="${targets} $(echo "$OPTARG" | tr ',' ' ')" ;;
    x) excludes="${excludes} $(echo "$OPTARG" | tr ',' ' ')" ;;
    f) [ -f "$OPTARG" ] && targets="${targets} $(cat "$OPTARG")" ;;
    e) [ -f "$OPTARG" ] && excludes="${excludes} $(cat "$OPTARG")" ;;
    o) outdir="$OPTARG" ;;
    p) ping_disable="-Pn" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "$timing_template" ] || [ -z "$targets" ]; then
  echo "Error: Must specify -T and targets (-t or -f)"
  usage
  exit 1
fi

mkdir -p "$outdir"
echo "[*] Results will be saved in: $outdir"
echo "[*] Log file: $logfile"

# prepare exclude option
exclude_option=""
[ -n "$excludes" ] && exclude_option="--exclude ${excludes}"

# main loop
for h in $targets; do
  host_name=$(echo "$h" | tr "/" "_")
  xml_file="${outdir}/${host_name}_syn_ping_${now}.xml"
  txt_file="${outdir}/${host_name}_syn_ping_${now}.txt"

  cmd="sudo nmap ${timing_template} ${exclude_option} -A ${ping_disable} -n \
-p- -PS22,80,443 -sS --host-timeout 30m \
-oX ${xml_file} -oN ${txt_file} ${h}"

  echo "[*] Now Launching: $cmd" | tee -a "$logfile"

  if ! eval "$cmd" >>"$logfile" 2>&1; then
    echo "[!] Scan failed: ${h}" | tee -a "$logfile"
    echo "$h" >> "$failed_hosts"
  fi
done

if [ -f "$failed_hosts" ]; then
  echo "[!] Some hosts failed to scan. See $failed_hosts"
fi
