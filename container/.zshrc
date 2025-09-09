# ==== safe tmux attach (interactive shells only) ====
if [[ $- == *i* ]] && command -v tmux >/dev/null 2>&1; then
  if ! tmux has-session -t works 2>/dev/null; then
    tmux new -ds works
  fi
  [ -z "$TMUX" ] && tmux attach -t works
fi



##### ============================================
##### Kali-on-macOS helper ~/.zshrc (Fixed)
#####  - X11 (XQuartz+socat), 永続/クリーン, Burp wrapper
#####  - VPN共有: NAT(utun)+rdr(1234/TCP) ON/OFF/RESET
#####  - pf完全停止の緊急復旧付き
##### ============================================

##### ---- PATHs ----
export PATH="$PATH:/opt/homebrew/opt/openvpn/sbin:/opt/X11/bin:/opt/homebrew/bin"

##### ---- cleanup (idempotent) ----
for a in container-pentest-clean container-pentest cpentest cpentest-clean \
         ckali ckali-clean ckali-rm ckali-exec \
         vpn-share-on vpn-share-off vpn-share-reset vpn-share-status \
         rshell-open rshell-close pf-panic-reset; do unalias "$a" 2>/dev/null; done
unset -f container_pentest_clean container_pentest \
          ckali_fn ckali_clean_fn ckali_rm_fn ckali_exec_fn \
          x11_up _host_ip _x11_bridge_up x11_down __apt_vols \
          _vpn_utun _kali_ip _ensure_pf_base \
          vpn-share-on vpn-share-off vpn-share-reset vpn-share-status \
          rshell-open rshell-close pf-panic-reset 2>/dev/null
unset _tool_bootstrap 2>/dev/null

##### ---- host ip ----
_host_ip() {
  local HIP; HIP="$(ipconfig getifaddr en0 2>/dev/null)"
  [ -z "$HIP" ] && HIP="$(ipconfig getifaddr en1 2>/dev/null)"
  [ -z "$HIP" ] && HIP="127.0.0.1"; printf "%s" "$HIP"
}

##### ---- X11 bridge ----
_x11_bridge_up() {
  pgrep -x XQuartz >/dev/null || { open -a XQuartz; sleep 1; }
  local LDISP; LDISP="$(launchctl getenv DISPLAY)"
  [ -z "$LDISP" ] && LDISP="$(ls -d /private/tmp/com.apple.launchd.* 2>/dev/null | head -n1)/org.xquartz:0"
  lsof -n -iTCP:6000 -sTCP:LISTEN | grep -q . || {
    nohup socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:"$LDISP" >/tmp/x11-socat.log 2>&1 &
    disown; for i in {1..20}; do lsof -n -iTCP:6000 -sTCP:LISTEN | grep -q . && break; sleep 0.25; done
  }
  DISPLAY=:0 /opt/X11/bin/xhost + >/dev/null 2>&1 || true
}
x11_down(){ DISPLAY=:0 /opt/X11/bin/xhost - >/dev/null 2>&1 || true; pkill -f 'socat TCP-LISTEN:6000' 2>/dev/null || true; }
x11_up(){ _x11_bridge_up; export DISPLAY="$(_host_ip):0"; }

##### ---- APT cache vols (optional) ----
__apt_vols(){
  local vols=(); if [ "${APT_PERSIST:-0}" = "1" ]; then
    if mkdir -p "$HOME/pentest/apt-cache" "$HOME/pentest/apt-lists" 2>/dev/null \
       && :> "$HOME/pentest/apt-cache/.touch" 2>/dev/null \
       && :> "$HOME/pentest/apt-lists/.touch" 2>/dev/null; then
      vols+=( --volume "$HOME/pentest/apt-cache:/var/cache/apt" )
      vols+=( --volume "$HOME/pentest/apt-lists:/var/lib/apt/lists" )
    else echo "[warn] apt-cache/lists をマウントしません（書込不可）" >&2; fi
  fi; printf "%s " "${vols[@]}"
}

##### ---- bootstrap inside Kali ----
read -r -d '' _tool_bootstrap <<'EOS'
set -e; umask 022
mkdir -p /var/cache/apt/archives /var/cache/apt/archives/partial /var/lib/apt/lists || true
chmod 755 /var/cache/apt/archives /var/lib/apt/lists 2>/dev/null || true
chmod 700 /var/cache/apt/archives/partial 2>/dev/null || true

if [ ! -f /root/.kali_bootstrapped ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -qq
  apt install -y --no-install-recommends \
    ca-certificates curl wget gnupg git tmux zsh nano vim build-essential \
    python3 python3-pip python3-venv python3-full python3-dev pipx golang-go jq \
    unzip xz-utils file tree lsof procps net-tools iproute2 dnsutils \
    x11-apps fonts-noto \
    nmap masscan netcat-traditional socat proxychains4 amass whatweb wafw00f nikto \
    gobuster ffuf feroxbuster dirb seclists wordlists \
    smbclient smbmap cifs-utils enum4linux-ng python3-impacket ldap-utils crackmapexec responder \
    metasploit-framework exploitdb sqlmap \
    chisel sshuttle mitmproxy tcpdump \
    burpsuite openjdk-21-jre openvpn iputils-ping inetutils-traceroute netcat-traditional dnsutils

  # Temurin 21（保険）
  mkdir -p /usr/share/keyrings
  if ! [ -f /usr/share/keyrings/adoptium.gpg ]; then
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg
    echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" >/etc/apt/sources.list.d/adoptium.list
    apt update -qq || true; apt install -y temurin-21-jre || true
  fi

  # Burp JAR（保険）
  [ -f /root/burpsuite-community.jar ] || curl -L -o /root/burpsuite-community.jar "https://portswigger.net/burp/releases/download?product=community&type=Jar" || true

  touch /root/.kali_bootstrapped
fi

# burp-light wrapper（プロファイル /mnt/burp-profile）
cat >/usr/local/bin/burp-light <<'BURP_EOF'
#!/bin/bash
set -euo pipefail
JAR="/root/burpsuite-community.jar"; [ -f /usr/share/burpsuite/burpsuite.jar ] && JAR="/usr/share/burpsuite/burpsuite.jar"
CANDIDATES=( "/usr/lib/jvm/temurin-21-jre-arm64/bin/java" "/usr/lib/jvm/java-21-openjdk-arm64/bin/java" "$(command -v java || true)" )
for c in "${CANDIDATES[@]}"; do [ -n "$c" ] && [ -x "$c" ] && JAVA="$c" && break; done
[ -n "${JAVA:-}" ] || { echo "[!] Java が見つかりません: apt install -y openjdk-21-jre"; exit 127; }
BASE="/mnt/burp-profile"; mkdir -p "$BASE/.java" "$BASE/.BurpSuite" "/tmp" 2>/dev/null || BASE="/tmp"
exec "$JAVA" -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel \
  -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true \
  -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false \
  -Duser.home="$BASE" -Djava.util.prefs.userRoot="$BASE/.java" -Djava.io.tmpdir=/tmp \
  -jar "$JAR" "$@"
BURP_EOF
chmod +x /usr/local/bin/burp-light

# 保険: 素ネット復旧のミニタスク（実行は手動）
cat >/usr/local/bin/net-repair <<'NR_EOF'
#!/bin/bash
set -e
ip route replace default via 192.168.64.1 dev eth0
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" >/etc/resolv.conf
echo "[+] routes/DNS refreshed"; ip route; cat /etc/resolv.conf
NR_EOF
chmod +x /usr/local/bin/net-repair
# --- MTU/PMTU チューニング（VPN経由の遅延・タイムアウト回避） ---
ip link set dev eth0 mtu 1500 2>/dev/null || true
sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.ip_no_pmtu_disc=0   >/dev/null 2>&1 || true

# 永続化（コンテナ内）
mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/99-mtu.conf <<'SYSCTL_EOF'
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0
SYSCTL_EOF

exec bash
EOS

##### ---- Clean run ----
ckali_clean_fn(){ x11_up; container run --rm -it \
  --env DISPLAY="$DISPLAY" --env XAUTHORITY="/dev/null" \
  --volume "$HOME:/mnt" --workdir /mnt $(__apt_vols) \
  docker.io/kalilinux/kali-rolling:latest bash -lc "$_tool_bootstrap"; }

##### ---- Persist run ----
ckali_fn(){
  x11_up; mkdir -p "$HOME/pentest/root"
  if container list --all | awk '{print $1}' | grep -qx ckali-persist; then
    echo "[*] Reattaching to existing ckali-persist container..."; container start -ai ckali-persist
  else
    echo "[*] Creating new ckali-persist container..."
    container run -it --name ckali-persist \
      --env DISPLAY="$DISPLAY" --env XAUTHORITY="/dev/null" \
      --volume "$HOME/pentest/root:/root" --volume "$HOME:/mnt" \
      --workdir /root $(__apt_vols) \
      docker.io/kalilinux/kali-rolling:latest bash -lc "$_tool_bootstrap"
  fi
}

ckali_exec_fn(){ container exec -it ckali-persist bash; }

ckali_rm_fn(){
  echo "[*] Removing ckali-persist container (if any)..."; container rm -f ckali-persist 2>/dev/null || true
  echo "[*] Removing persistent directories under ~/pentest ...";
  rm -rf "$HOME/pentest/root" "$HOME/pentest/apt-cache" "$HOME/pentest/apt-lists" "$HOME/pentest/burp-profile"
  echo "[*] Done. ckali environment wiped."
}

# --- Kali の IP を eth0 から直接取得 ---
_kali_ip() {
  container exec ckali-persist sh -lc \
    'ip -4 -o addr show eth0 2>/dev/null | awk "{print \$4}" | cut -d/ -f1' \
    2>/dev/null | head -n1
}

# --- utun の自動検出（10.x が付いてるもの） ---
_vpn_utun() {
  ifconfig | awk '
    /^[[:alnum:]]/ { i=$1; sub(":","",i) }
    /inet 10\./ && i ~ /^utun[0-9]+$/ { print i; exit }
  '
}

# --- pf のベース（順序厳守: options -> normalization -> translation -> filtering(anchors)） ---
_ensure_pf_base() {
  sudo pfctl -E >/dev/null 2>&1 || true
  cat <<'EOF' | sudo pfctl -q -f -
set skip on lo0

scrub-anchor "com.apple/*"

nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"

# 我々のアンカーは translation の後で呼び出す
nat-anchor "com.pentest.vpnshare"
rdr-anchor "com.pentest.vpnshare"
anchor "com.pentest.vpnshare"
EOF
}

# --- OFF: 我々のアンカーを空にして、pf は維持（安全に戻す） ---
vpn-share-off() {
  echo "[*] Flushing our anchor only..."
  sudo pfctl -q -a com.pentest.vpnshare -F all >/dev/null 2>&1 || true

  # ベースのみ残す（Apple側アンカーは維持）
  cat <<'EOF' | sudo pfctl -q -f -
set skip on lo0

scrub-anchor "com.apple/*"

nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"

nat-anchor "com.pentest.vpnshare"
rdr-anchor "com.pentest.vpnshare"
anchor "com.pentest.vpnshare"
EOF

  # 転送は好みでOFF（ONのままでもOKならコメントアウト可）
  # sudo sysctl -w net.inet.ip.forwarding=0 >/dev/null

  echo "[+] VPN sharing is OFF (pf stays enabled)."
}

# --- RESET: pf 全停止→デフォルトへ完全復旧（最終手段） ---
vpn-share-reset() {
  echo "[*] Disabling pf & clearing rules..."
  sudo pfctl -d >/dev/null 2>&1 || true
  sudo pfctl -Fa -f /etc/pf.conf >/dev/null 2>&1 || true
  sudo sysctl -w net.inet.ip.forwarding=0 >/dev/null
  echo "[+] pf reset complete."
}

# --- ON: NAT(utun) + rdr(utun:1234 -> KALI_IP:1234) [順序修正版] ---
vpn-share-on() {
  # 初期状態に戻す
  vpn-share-off
  vpn-share-reset

  local UTUN="$(_vpn_utun)"
  if [ -z "$UTUN" ]; then
    echo "[!] utun未検出。先にVPN接続してください"; return 1
  fi

  local KIP
  if ! KIP="$(_kali_ip)"; then
    echo "[!] Kali IP を特定できません。KALI_IP=192.168.64.x を指定して再実行してください"
    return 1
  fi

  local RPORT="${VPN_RPORT:-1234}"
  echo "[*] Using utun: $UTUN"
  echo "[*] Kali IP  : $KIP"
  echo "[*] Rdr Port : $RPORT"

  _ensure_pf_base

  # ★ ここが肝心：translation（rdr, nat）→ filtering（pass）の順
  cat <<EOF | sudo pfctl -q -a com.pentest.vpnshare -f -
rdr pass on $UTUN inet proto tcp from any to ($UTUN) port $RPORT -> $KIP port $RPORT
nat on $UTUN inet from 192.168.64.0/24 to any -> ($UTUN)
pass out on $UTUN inet from 192.168.64.0/24 to any keep state
EOF

  sudo sysctl -w net.inet.ip.forwarding=1 >/dev/null

  echo "[+] VPN sharing is ON via $UTUN"
  echo "[i] Kaliで:  nc -lvnp $RPORT"
  echo "[i] Payload LHOST=あなたの $UTUN の inet(10.x.x.x), LPORT=$RPORT"
}

# --- rshell-open も同じ順序に修正（任意で使っている場合のみ差し替え） ---
rshell-open(){
  local UTUN="$(_vpn_utun)"; [ -z "$UTUN" ] && { echo "[!] utun未検出"; return 1; }
  local KIP="$(_kali_ip)" RPORT="${VPN_RPORT:-1234}"; _ensure_pf_base
  cat <<EOF | sudo pfctl -q -a com.pentest.vpnshare -f -
rdr pass on $UTUN inet proto tcp from any to ($UTUN) port $RPORT -> $KIP port $RPORT
nat on $UTUN inet from 192.168.64.0/24 to any -> ($UTUN)
pass out on $UTUN inet from 192.168.64.0/24 to any keep state
EOF
  sudo sysctl -w net.inet.ip.forwarding=1 >/dev/null
  echo "[+] rdr enabled ($UTUN:$RPORT -> $KIP:$RPORT)"
}

# --- STATUS: 一括確認 ---
vpn-share-status() {
  echo "== main rules ==";      sudo pfctl -sr
  echo "== nat rules  ==";      sudo pfctl -sn
  echo "== our anchor (rules) =="; sudo pfctl -a com.pentest.vpnshare -sr
  echo "== our anchor (nat)   =="; sudo pfctl -a com.pentest.vpnshare -sn
  echo "== forwarding ==";      sysctl net.inet.ip.forwarding
}

kali-set-mtu() {
  local MTU="${1:-1500}"
  echo "[*] Set Kali eth0 MTU = $MTU"
  container exec ckali-persist sh -lc "ip link set dev eth0 mtu $MTU && ip a s eth0 | sed -n '1,3p'"
}

##### ---- aliases ----
alias ckali='ckali_fn'
alias ckali-clean='ckali_clean_fn'
alias ckali-rm='ckali_rm_fn'
alias ckali-exec='ckali_exec_fn'
alias container-pentest='ckali_fn'
alias container-pentest-clean='ckali_clean_fn'
alias cpentest='ckali_fn'
alias cpentest-clean='ckali_clean_fn'

container system start

##### ---- on-load hint ----
if [ -z "$ZSHRC_KALI_HINT_SHOWN" ]; then export ZSHRC_KALI_HINT_SHOWN=1; cat <<'HINT'
[helper]
- 永続Kali:        ckali          / 別タブ: ckali-exec
- 使い捨てKali:    ckali-clean
- 全破棄:          ckali-rm
- Burp:            burp-light（Kali内）
- VPN共有 ON:      vpn-share-on   （utun NAT + rdr:1234）
- VPN共有 OFF:     vpn-share-off  （pf停止/既定復帰）
- pf 完全初期化:    vpn-share-reset / pf-panic-reset
- Kaliネット復旧:   （Kali内） net-repair
HINT
fi
