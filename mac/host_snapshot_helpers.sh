#!/usr/bin/env bash
# mac/host_snapshot_helpers.sh — macOS host snapshot helper
set -euo pipefail

OUTBASE="${OUTBASE:-$HOME/pentest/vm/Kali-Host-Snapshots}"
SHARED_ROOT="${$HOME/pentest/vm/share/kali}"
TS="$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$OUTBASE"

pick_shared(){F
  # 共有フォルダ（1つでも見つかれば使う）
  if [ -d "$SHARED_ROOT" ]; then
    # 最初の共有を選択（環境に応じて変更可）
    local first_share
    first_share="$(ls -1 "$SHARED_ROOT" 2>/dev/null | head -n1 || true)"
    if [ -n "$first_share" ] && [ -d "$SHARED_ROOT/$first_share" ]; then
      echo "$SHARED_ROOT/$first_share"
      return 0
    fi
  fi
  return 1
}

snapshot_macos(){
  local out="$OUTBASE/host_snapshot_macos-$TS.txt"
  {
    echo "== sw_vers =="; sw_vers
    echo; echo "== uname -a =="; uname -a
    echo; echo "== system_profiler (mini) =="; system_profiler SPSoftwareDataType SPHardwareDataType -detailLevel mini 2>/dev/null || true
    echo; echo "== ifconfig -a =="; ifconfig -a
    echo; echo "== networksetup -listallhardwareports =="; networksetup -listallhardwareports
    echo; echo "== routes (netstat -rn) =="; netstat -rn
    echo; echo "== DNS (scutil --dns) =="; scutil --dns
    echo; echo "== utun interfaces =="; ifconfig | awk '/^utun/{print $1}'; echo
    echo; echo "== pf (rules/nat/state) =="; pfctl -sr 2>/dev/null; pfctl -sn 2>/dev/null; pfctl -si 2>/dev/null
    echo; echo "== processes (vmware/openvpn/wireguard etc.) =="; ps aux | egrep -i 'vmware|openvpn|wireguard|tailscale|zerotier' | egrep -v 'egrep' || true
    local vmnet_cli="/Applications/VMware Fusion.app/Contents/Library/vmnet-cli"
    if [ -x "$vmnet_cli" ]; then echo; echo "== vmnet-cli --status =="; "$vmnet_cli" --status 2>/dev/null || true; fi
    echo; echo "== brew list --versions =="; command -v brew >/dev/null 2>&1 && brew list --versions || echo "(brew not found)"
  } > "$out"
  echo "[+] saved: $out"

  if share="$(pick_shared)"; then
    local dst="$share/KaliHostLogs"
    mkdir -p "$dst"
    cp -f "$out" "$dst/" && echo "[+] copied to Shared: $dst"
  fi
}

case "${1:-run}" in
  run|snapshot) snapshot_macos ;;
  *) echo "Usage: $0 [run]"; exit 1 ;;
esac