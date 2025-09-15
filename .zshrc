# =====================================================================
# ~/.zshrc — macOS 専用
#   - WezTerm 設定を自動生成（~/.wezterm.lua と ~/.config/wezterm/wezterm.lua）
#   - 自動起動なし。分割: Ctrl+h(水平) / Ctrl+v(垂直) ※Ctrl+Backspace=水平
#   - Cmd+C/Cmd+V コピー/ペースト
#   - 見た目: Tokyo Night Storm + 半透明 + ブラー + タイトルバー表示
#   - zsh カラー強化: syntax-highlighting / autosuggestions（在れば）
#   - 使い勝手: カラープロンプト（Git 情報）、Bracketed Paste 無効化
#   - Kali コンテナ環境ヘルパー（ckali / vpn-share-* など）
#   - tmux 自動起動は無効（スニペットはコメントで残置）
# =====================================================================

##### ---- PATHs ----
export PATH="$PATH:/opt/homebrew/opt/openvpn/sbin:/opt/X11/bin:/opt/homebrew/bin"

# ==== safe tmux auto-attach (interactive ONLY; skip VSCode/JetBrains/SSH) ====
# 【Macでは tmux 自動起動は無効】
# if [ -n "$PS1" ] && [ -z "$TMUX" ] && [ -t 0 ]; then
#   case "$TERM_PROGRAM" in
#     "vscode"|"JetBrains") : ;;
#     *)
#       if [ -z "$SSH_TTY" ] && command -v tmux >/dev/null 2>&1; then
#         TMUX_SESSION="${TMUX_SESSION:-works}"
#         tmux has-session -t "$TMUX_SESSION" 2>/dev/null \
#           && exec tmux attach -t "$TMUX_SESSION"
#         exec tmux new -s "$TMUX_SESSION"
#       fi
#     ;;
#   esac
# fi

# ---- WezTerm config auto-setup (no auto-launch) ----
# 不整合を避けるため両パスに同内容を書き出し。SF Mono は参照しない。
_wez_paths=("$HOME/.wezterm.lua" "$HOME/.config/wezterm/wezterm.lua")
mkdir -p "$HOME/.config/wezterm"
for _p in "${_wez_paths[@]}"; do : >"$_p"; done
cat > "$HOME/.wezterm.lua" <<'LUA'
local wezterm = require 'wezterm'
local act = wezterm.action
local bg = os.getenv("WEZTERM_BG") or ""   -- 任意：背景画像パス

return {
  -- フォント（SF Mono 非依存）
  font = wezterm.font_with_fallback({
    "Menlo", "JetBrains Mono", "FiraCode Nerd Font Mono", "Monaco",
    "Noto Sans Mono CJK JP", "DejaVu Sans Mono"
  }),
  font_size = 13.0,
  harfbuzz_features = { "liga=1", "clig=1", "calt=1" },

  -- 見た目
  color_scheme = "Tokyo Night Storm",
  hide_tab_bar_if_only_one_tab = true,
  use_fancy_tab_bar = true,
  enable_scroll_bar = false,
  -- タイトルバー（閉じる/最小化/最大化ボタン）を表示
  window_decorations = "TITLE|RESIZE",
  window_background_opacity = 0.93,
  text_background_opacity   = 1.0,
  macos_window_background_blur = 18,
  inactive_pane_hsb = { saturation = 0.9, brightness = 0.55 },
  window_padding = { left = 6, right = 6, top = 6, bottom = 6 },

  -- 背景画像（任意）
  window_background_image = (bg ~= "" and bg or nil),
  window_background_image_hsb = (bg ~= "" and { brightness = 0.08, hue = 1.0, saturation = 1.0 } or nil),

  -- キーバインド
  keys = {
    -- Copy/Paste（Cmd）
    { key = "c", mods = "CMD",  action = act.CopyTo "Clipboard" },
    { key = "v", mods = "CMD",  action = act.PasteFrom "Clipboard" },

    -- 分割: Ctrl+h(水平) / Ctrl+v(垂直)
    { key = "h",         mods = "CTRL", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "Backspace", mods = "CTRL", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } }, -- ^H対策
    { key = "b",         mods = "CTRL", action = act.SplitVertical   { domain = "CurrentPaneDomain" } },

    -- タブ
    { key = "t", mods = "CMD", action = act.SpawnTab "CurrentPaneDomain" },
    { key = "w", mods = "CMD", action = act.CloseCurrentTab { confirm = true } },
    { key = "q", mods = "CMD", action = act.QuitApplication },
  },

  check_for_updates = false,
}
LUA
# 同じ内容を ~/.config/wezterm/wezterm.lua にも反映
cp -f "$HOME/.wezterm.lua" "$HOME/.config/wezterm/wezterm.lua" 2>/dev/null || true

# ---- zsh: Bracketed Paste を全体で無効 ----
disable_bracketed_paste() { printf '\e[?2004l'; }
autoload -Uz add-zsh-hook 2>/dev/null || true
add-zsh-hook precmd disable_bracketed_paste
add-zsh-hook preexec disable_bracketed_paste
zle -N bracketed-paste self-insert 2>/dev/null || true

# ---- zsh: カラー強化（在れば自動）----
# Homebrew: brew install zsh-syntax-highlighting zsh-autosuggestions
if [ -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
if [ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6b7280'  # subtle gray
fi

# ---- カラープロンプト（Git ブランチ/dirty 表示）----
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats '(%b%u%c)'
precmd() { vcs_info }
setopt PROMPT_SUBST
PROMPT='%F{81}%n%f@%F{75}%m%f %F{117}%~%f ${vcs_info_msg_0_:+%F{180}$vcs_info_msg_0_%f}
%F{34}➜%f '

# ls や grep をカラー出力
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad
export GREP_OPTIONS='--color=auto'
export GREP_COLOR='1;32'

# ==========================================================
# 以降は「Kali-on-macOS helper」ブロック（省略せずそのまま）
# ==========================================================

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

##### ---- PATHs ----
export PATH="$PATH:/opt/homebrew/opt/openvpn/sbin:/opt/X11/bin:/opt/homebrew/bin"

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

##### ---- bootstrap inside Kali (container CLEAN/PERSIST setup) ----
read -r -d '' _tool_bootstrap <<'EOS'
set -e; umask 022
mkdir -p /var/cache/apt/archives /var/cache/apt/archives/partial /var/lib/apt/lists || true
chmod 755 /var/cache/apt/archives /var/lib/apt/lists 2>/dev/null || true
chmod 700 /var/cache/apt/archives/partial 2>/dev/null || true

if [ ! -f /root/.kali_bootstrapped ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -qq
  apt install -y --no-install-recommends \
    ca-certificates curl wget gnupg git zsh nano vim build-essential \
    python3 python3-pip python3-venv python3-full python3-dev pipx golang-go jq \
    unzip xz-utils file tree lsof procps net-tools iproute2 dnsutils \
    x11-apps fonts-noto \
    nmap masscan netcat-traditional socat proxychains4 amass whatweb wafw00f nikto \
    gobuster ffuf feroxbuster dirb seclists wordlists \
    smbclient smbmap cifs-utils enum4linux-ng python3-impacket ldap-utils crackmapexec responder \
    metasploit-framework exploitdb sqlmap \
    chisel sshuttle mitmproxy tcpdump \
    burpsuite openjdk-21-jre openvpn iputils-ping inetutils-traceroute netcat-traditional dnsutils

  mkdir -p /usr/share/keyrings
  if ! [ -f /usr/share/keyrings/adoptium.gpg ]; then
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg
    echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" >/etc/apt/sources.list.d/adoptium.list
    apt update -qq || true; apt install -y temurin-21-jre || true
  fi

  [ -f /root/burpsuite-community.jar ] || curl -L -o /root/burpsuite-community.jar "https://portswigger.net/burp/releases/download?product=community&type=Jar" || true

  touch /root/.kali_bootstrapped
fi

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

cat >/usr/local/bin/net-repair <<'NR_EOF'
#!/bin/bash
set -e
ip route replace default via 192.168.64.1 dev eth0
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" >/etc/resolv.conf
echo "[+] routes/DNS refreshed"; ip route; cat /etc/resolv.conf
NR_EOF
chmod +x /usr/local/bin/net-repair

ip link set dev eth0 mtu 1500 2>/dev/null || true
sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.ip_no_pmtu_disc=0   >/dev/null 2>&1 || true

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

_kali_ip() {
  container exec ckali-persist sh -lc \
    'ip -4 -o addr show eth0 2>/dev/null | awk "{print \$4}" | cut -d/ -f1' \
    2>/dev/null | head -n1
}

_vpn_utun() {
  ifconfig | awk '
    /^[[:alnum:]]/ { i=$1; sub(":","",i) }
    /inet 10\./ && i ~ /^utun[0-9]+$/ { print i; exit }
  '
}

_ensure_pf_base() {
  sudo pfctl -E >/dev/null 2>&1 || true
  cat <<'EOF' | sudo pfctl -q -f -
set skip on lo0
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
nat-anchor "com.pentest.vpnshare"
rdr-anchor "com.pentest.vpnshare"
anchor "com.pentest.vpnshare"
EOF
}

vpn-share-off() {
  echo "[*] Flushing our anchor only..."
  sudo pfctl -q -a com.pentest.vpnshare -F all >/dev/null 2>&1 || true
  cat <<'EOF' | sudo pfctl -q -f -
set skip on lo0
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
nat-anchor "com.pentest.vpnshare"
rdr-anchor "com.pentest.vpnshare"
anchor "com.pentest.vpnshare"
EOF
  echo "[+] VPN sharing is OFF (pf stays enabled)."
}

vpn-share-reset() {
  echo "[*] Disabling pf & clearing rules..."
  sudo pfctl -d >/dev/null 2>&1 || true
  sudo pfctl -Fa -f /etc/pf.conf >/dev/null 2>&1 || true
  sudo sysctl -w net.inet.ip.forwarding=0 >/dev/null
  echo "[+] pf reset complete."
}

vpn-share-on() {
  vpn-share-off
  vpn-share-reset
  local UTUN="$(_vpn_utun)"
  if [ -z "$UTUN" ]; then echo "[!] utun未検出。先にVPN接続してください"; return 1; fi
  local KIP; if ! KIP="$(_kali_ip)"; then echo "[!] Kali IP 不明"; return 1; fi
  local RPORT="${VPN_RPORT:-1234}"
  echo "[*] Using utun: $UTUN"; echo "[*] Kali IP  : $KIP"; echo "[*] Rdr Port : $RPORT"
  _ensure_pf_base
  cat <<EOF | sudo pfctl -q -a com.pentest.vpnshare -f -
rdr pass on $UTUN inet proto tcp from any to ($UTUN) port $RPORT -> $KIP port $RPORT
nat on $UTUN inet from 192.168.64.0/24 to any -> ($UTUN)
pass out on $UTUN inet from 192.168.64.0/24 to any keep state
EOF
  sudo sysctl -w net.inet.ip.forwarding=1 >/dev/null
  echo "[+] VPN sharing is ON via $UTUN"
  echo "[i] Kaliで:  nc -lvnp $RPORT"
}

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
- VPN共有 OFF:     vpn-share-off
- pf 完全初期化:    vpn-share-reset
- Kaliネット復旧:   （Kali内） net-repair
- 分割: Ctrl+h(水平) / Ctrl+v(垂直) ※Ctrl+Backspace=水平
- Cmd+C/Cmd+V コピー/ペースト
HINT
fi