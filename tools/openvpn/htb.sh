#!/bin/bash
# Hack The Box VPN Troubleshooting (HTB版)
# v1.0 (2025-09-24)
# Author: ChatGPT (adapted for HTB)
#
# 目的:
#  - OpenVPN 接続の基本トラブルを自動検査・簡易修復
#  - HTB 環境におけるレンジ/MTU/多重接続 などをチェック
#
# 注意:
#  - 権限/規約に従って自己責任で実行してください
#  - HTB はリージョンやプランによりIPレンジが異なる場合があります
#  - 固定のゲートウェイIPに依存せず、一般的レンジ/疎通で判定します

set -euo pipefail

########################################
# 色
########################################
colour(){
  if [ $# -lt 2 ]; then return 1; fi
  case "$1" in
    green)   printf "\033[01;32m%s\033[0m\n" "$2" ;;
    red)     printf "\033[01;31m%s\033[0m\n" "$2" ;;
    yellow)  printf "\033[01;93m%s\033[0m\n" "$2" ;;
    header)  printf "\033[0;1;4m%s\033[0m\n" "$2" ;;
    code)    printf "\033[01;31;47m%s\033[0m\n" "$2" ;;
    process) printf "\033[01;94m%s\033[0m\n" "$2" ;;
    warning) printf "\033[01;93m[Warning!]\033[0m %s\n" "$2" ;;
    *) return 1 ;;
  esac
  if [ $# -eq 3 ]; then sleep "$3"s; fi
}

########################################
# バナー
########################################
title(){
  printf "\n\n\033[0;1;32m"
  cat << "EOF"
 _   _ _____ _____            _   _     _______        _     
| | | |_   _|_   _|__   ___  | | | |___|__   __|__  __| |___ 
| |_| | | |   | |/ _ \ / __| | | | / __|  | |/ _ \/ _` / __|
|  _  | | |   | | (_) | (__  | |_| \__ \  | |  __/ (_| \__ \
|_| |_| |_|   |_|\___/ \___|  \___/|___/  |_|\___|\__,_|___/
               Hack The Box VPN Troubleshooter
EOF
  printf "\033[0m\n"
}

########################################
# フィニッシュ
########################################
fin(){ printf "\n"; exit 1; }

########################################
# OpenVPN 接続（自動試行）
########################################
connect(){
  # $ovpn 必要
  local ovpnoutput
  ovpnoutput=$(mktemp)

  testSuccess() { grep -qio "Initialization Sequence Completed" "$ovpnoutput"; }
  testCertErr() { grep -qioE "Cannot load inline certificate file|certificate verify failed|cannot load CA" "$ovpnoutput"; }
  testCipherSwitchNeeded() { grep -qioE "cipher AES-256-CBC" "$ovpn"; }

  # 非対話でログのみ
  sudo openvpn "$ovpn" </dev/null &>"$ovpnoutput" &
  colour process "[+] Connecting with OpenVPN..." 8

  for i in 1 2; do
    if testSuccess; then
      colour green "[+] OpenVPN initialization completed!"
      return 0
    elif testCertErr; then
      killall -9 openvpn &>/dev/null || true
      colour red "[-] Fatal: Certificate/CA error detected."
      printf "HTBポータルでVPN設定(.ovpn)を再生成し、サーバを変えて再生成も試してください。\n"
      return 1
    elif testCipherSwitchNeeded; then
      # 旧式cipher -> data-ciphers へ置換（互換目的）
      colour yellow "[!] Outdated cipher directive detected. Patching to data-ciphers..."
      sed -i 's/^cipher AES-256-CBC/data-ciphers AES-256-CBC/' "$ovpn"
      colour green "[+] Patched. 再接続コマンド:\n"
      colour code "sudo openvpn \"$ovpn\""
      killall -9 openvpn &>/dev/null || true
      return 1
    fi

    if [ "$i" -eq 1 ]; then
      colour warning "Connection is taking longer than expected..."
      sleep 12
    else
      colour red "[-] Failed to connect automatically."
      printf "対処:\n"
      printf " - HTBポータルでVPN設定を再生成\n"
      printf " - 別サーバへ切替後に再生成\n"
      printf " - システム時刻ずれの確認\n"
      killall -9 openvpn &>/dev/null || true
      return 1
    fi
  done
}

########################################
# 事前チェック: 権限
########################################
title
if [ "$EUID" -ne 0 ]; then
  colour red "[-] このスクリプトは root での実行を推奨します。"
  read -rp "sudoで再実行しますか？ (Y/n): " choice
  case "${choice:-Y}" in
    n|N) colour code "sudo $0" ; fin ;;
    *) exec sudo -E "$0" ;;
  esac
fi

########################################
# .ovpn 検出
########################################
ovpn=$(find . -maxdepth 1 -name "*.ovpn" -print -quit 2>/dev/null || true)
if [ -z "${ovpn:-}" ]; then
  colour red "[-] カレントに .ovpn が見つかりません。"
  read -erp "HTBの .ovpn ファイルのパスを入力: " ovpn
  ovpn=${ovpn/\~/$HOME}
fi
if [ ! -f "$ovpn" ] || [[ "$ovpn" != *.ovpn ]]; then
  colour red "[-] .ovpn ファイルが不正です。"; fin
fi
colour green "[+] .ovpn: $ovpn"

########################################
# ネット接続確認
########################################
if ! ping -c1 -W1 1.1.1.1 &>/dev/null; then
  colour red "[-] インターネット未接続。まず外部ネット疎通を確認してください。"
  fin
fi
colour green "[+] インターネット疎通OK"

########################################
# パッケージマネージャ検出 & OpenVPN 確認
########################################
is_openvpn_installed(){ command -v openvpn &>/dev/null; }

pkg_mgr=""
if command -v pacman &>/dev/null; then pkg_mgr="pacman"
elif command -v apt &>/dev/null; then pkg_mgr="apt"
fi

if ! is_openvpn_installed; then
  colour red "[-] OpenVPN が未インストール"
  read -rp "自動インストールしますか？ (Y/n): " choice
  case "${choice:-Y}" in
    n|N) colour code "sudo ${pkg_mgr:-apt} install openvpn" ; fin ;;
    *)
      if [ "$pkg_mgr" = "pacman" ]; then
        pacman -Syy --noconfirm && pacman -S --noconfirm openvpn || { colour red "[-] 失敗"; fin; }
      else
        apt update && apt install -y openvpn || { colour red "[-] 失敗"; fin; }
      fi
      colour green "[+] OpenVPN インストール完了"
      ;;
  esac
else
  colour green "[+] OpenVPN インストール済み"
fi

########################################
# tun0 存在確認 & 自動接続
########################################
if ! ip link show tun0 &>/dev/null; then
  colour yellow "[!] tun0 が見つかりません。接続を試みます。"
  if ! connect; then fin; fi
  sleep 2
fi
colour green "[+] tun0 存在OK"

########################################
# HTB想定レンジ確認 (クライアント側: 10.10.0.0/16 想定が多い)
########################################
tun4cidr=$(ip -4 addr show dev tun0 | awk '/inet /{print $2}')
tun4ip=$(ip -4 addr show dev tun0 | awk '/inet /{print $2}' | cut -d/ -f1)

if [[ -z "${tun4ip:-}" ]]; then
  colour red "[-] tun0 に IPv4 が割り当てられていません。"
  fin
fi

if echo "$tun4ip" | grep -Eq '^10\.10\.[0-9]{1,3}\.[0-9]{1,3}$'; then
  colour green "[+] tun0 IP in HTB-like range: $tun4ip ($tun4cidr)"
else
  colour yellow "[!] tun0 IP ($tun4ip) が HTBの一般的レンジ(10.10.0.0/16)と異なる可能性。"
  colour yellow "    * リージョン/プランにより割当レンジが異なることがあります。"
fi

########################################
# 多重 OpenVPN プロセス検出
########################################
connections=$(ps aux | grep -v "sudo\|grep" | grep -Eo "openvpn .*\.ovpn" | wc -l)
if [ "$connections" -gt 1 ]; then
  colour red "[-] 複数の OpenVPN 接続が動作中です。"
  read -rp "重複プロセスを停止しますか？ (Y/n): " choice
  case "${choice:-Y}" in
    n|N)
      colour code "sudo killall -9 openvpn"
      fin
      ;;
    *)
      killall -9 openvpn || true
      colour green "[+] 重複プロセスを停止しました。"
      # 必要なら再接続
      if ! connect; then fin; fi
      ;;
  esac
else
  colour green "[+] OpenVPN の多重接続なし"
fi

########################################
# MTU チェック & 自動最適化
########################################
origin_mtu=$(cat /sys/class/net/tun0/mtu 2>/dev/null || echo 1500)
mtu=$(( origin_mtu - 30 ))
test_host_candidates=("10.10.10.10" "10.129.0.1")

colour process "[+] MTU 最適化を試行します..."

try_ping_mtu(){
  local size="$1" host="$2"
  ping -M do -s "$size" -W 1 -c 1 "$host" &>/dev/null
}

# 候補ホストのどれかに通ればOKという方針
chosen_host=""
for h in "${test_host_candidates[@]}"; do
  if ping -c1 -W1 "$h" &>/dev/null; then chosen_host="$h"; break; fi
done
# どれも疎通しない場合でも、MTU調整は一応実行しておく(効果があるケースあり)
[ -z "$chosen_host" ] && chosen_host="10.10.10.10"

while true; do
  if try_ping_mtu "$mtu" "$chosen_host"; then
    mtu=$(( mtu + 30 ))
    if [ "$mtu" -eq "$origin_mtu" ]; then
      colour green "[+] MTU OK ($origin_mtu)"
      break
    else
      colour yellow "[!] 元のMTU($origin_mtu)では断片化の可能性。tun0を $mtu に調整します。"
      ip link set dev tun0 mtu "$mtu" || true
      colour green "[+] tun0 MTU を $mtu に設定しました。"
      read -rp "ovpn に恒久設定 (tun-mtu $mtu) を追記しますか？ (Y/n): " choice
      case "${choice:-Y}" in
        n|N) colour code "tun-mtu $mtu  # を .ovpn に手動追記可" ;;
        *)
          if grep -q "^tun-mtu " "$ovpn"; then
            sed -i "s/^tun-mtu .*/tun-mtu $mtu/" "$ovpn"
          else
            sed -i "1itun-mtu $mtu" "$ovpn"
          fi
          colour green "[+] .ovpn に tun-mtu $mtu を設定しました。"
          ;;
      esac
      break
    fi
  else
    if [ "$mtu" -lt 1000 ]; then
      colour red "[-] MTU 1000 未満でも疎通安定せず。別経路/回線や TCP版.ovpn を検討してください。"
      break
    fi
    mtu=$(( mtu - 30 ))
  fi
done

########################################
# 最終疎通確認
########################################
colour process "[+] 最終チェック: 代表セグメント疎通とIP表示"

ok=false
# 代表的セグメントへの疎通（どちらか通ればOK）
if ping -c1 -W1 10.10.10.10 &>/dev/null; then ok=true; fi
if ping -c1 -W1 10.129.0.1 &>/dev/null; then ok=true; fi

if $ok; then
  colour green "[+] HTBネットワーク到達性: OK"
else
  colour yellow "[!] 代表セグメントへのICMP応答が無いですが、環境によりICMP遮断もあり得ます。"
  colour yellow "    nmapや実際のターゲットへのTCP接続で最終確認してください。"
fi

# 自身のVPN IP 表示（tun0）
colour green "[+] あなたの VPN(tun0) IPv4: $tun4ip ($tun4cidr)"

# 参考: ルート状況
colour process "[i] 主要ルート (tun0):"
ip route show dev tun0 || true

colour green "Happy Hacking on HTB!"; exit 0