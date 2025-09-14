#!/usr/bin/env bash
# ==============================================================================
# kali-bootstrap.sh — Reproducible Kali-on-VM setup (GUI, tools, IME, Cmd shortcuts,
#                     Shared folder helper, OpenVPN helpers, proofshot, WezTerm, Remmina)
# ==============================================================================

set -euo pipefail

LOG="/var/log/kali-bootstrap.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
[ "${DEBUG:-0}" = "1" ] && set -x
trap 'echo "[!] Error (line $LINENO). See $LOG"' ERR
step(){ printf '\n\033[1;32m[STEP]\033[0m %s\n\n' "$*"; }
note(){ printf '\033[0;36m[i]\033[0m %s\n' "$*"; }
ok(){   printf '\033[0;32m[+]\033[0m %s\n' "$*"; }

require_root(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Run as root: sudo bash $0"
    exit 1
  fi
}

detect_main_user(){
  local u="${SUDO_USER:-}"
  if [ -z "$u" ] || [ "$u" = "root" ]; then u="$(logname 2>/dev/null || true)"; fi
  if [ -z "$u" ] || [ "$u" = "root" ]; then u="$(awk -F: '$3==1000{print $1; exit}' /etc/passwd || true)"; fi
  echo "$u"
}

main(){
  require_root
  export DEBIAN_FRONTEND=noninteractive

  MAIN_USER="$(detect_main_user)"
  MAIN_HOME=""
  if [ -n "$MAIN_USER" ] && [ "$MAIN_USER" != "root" ]; then
    MAIN_HOME="$(getent passwd "$MAIN_USER" | cut -d: -f6)"
  fi
  note "main user : ${MAIN_USER:-<none>}"
  note "main home : ${MAIN_HOME:-<n/a>}"

  # ---------- A. Base ----------
  step "APT update & base packages"
  apt update -qq
  apt install -y --no-install-recommends \
    ca-certificates curl wget gnupg git zsh nano vim build-essential jq unzip xz-utils \
    file tree lsof procps net-tools iproute2 dnsutils \
    xclip xdg-user-dirs xdg-utils fonts-noto-cjk fonts-dejavu-core \
    xbindkeys xdotool \
    open-vm-tools-desktop \
    xfce4-terminal firefox-esr \
    resolvconf openvpn scrot imagemagick \
    python3 python3-pip python3-venv python3-full python3-dev pipx golang-go \
    nmap masscan netcat-traditional socat proxychains4 amass whatweb wafw00f nikto \
    gobuster ffuf feroxbuster dirb seclists wordlists \
    smbclient smbmap cifs-utils enum4linux-ng python3-impacket ldap-utils crackmapexec responder \
    metasploit-framework exploitdb sqlmap \
    chisel sshuttle mitmproxy tcpdump
  ok "Base toolchain installed"

  # ---------- A2. WezTerm repo ----------
  step "Configuring WezTerm official APT repo (apt.fury.io/wez)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://apt.fury.io/wez/gpg.key | gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
  chmod 644 /usr/share/keyrings/wezterm-fury.gpg
  echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' \
    >/etc/apt/sources.list.d/wezterm.list
  apt update -qq
  apt install -y wezterm fonts-jetbrains-mono fonts-firacode || true
  ok "WezTerm + fonts installed"

  # ---------- A3. VS Code ----------
  step "Installing VS Code (Deb822 repo)"
  install -d -m 0755 /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/microsoft.gpg ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
    chmod 0644 /etc/apt/keyrings/microsoft.gpg
  fi
  rm -f /etc/apt/sources.list.d/vscode.list 2>/dev/null || true
  sed -i -E 's#^(deb .*packages.microsoft.com/repos/code .*)#\# \1#g' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
  cat >/etc/apt/sources.list.d/vscode.sources <<'SRC'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /etc/apt/keyrings/microsoft.gpg
SRC
  apt update -qq || true
  apt install -y code || true
  ok "VS Code installed"

  # ---------- A4. Remmina ----------
  step "Installing Remmina (RDP/Secret plugins)"
  apt install -y remmina remmina-plugin-rdp remmina-plugin-secret || true
  ok "Remmina installed"

  # ---------- B. Desktop/IME ----------
  if [ "${SKIP_FULL:-0}" != "1" ]; then
    step "Installing Desktop & kali-linux-default"
    apt install -y kali-desktop-xfce kali-linux-default
  fi
  ok "Desktop meta packages handled"

  step "IME: fcitx5-mozc"
  apt install -y --no-install-recommends fcitx5 fcitx5-mozc fcitx5-config-qt im-config
  if [ -n "$MAIN_HOME" ]; then
    install -d -m 0755 "$MAIN_HOME/.config"
    if ! grep -q 'fcitx5 -dr' "$MAIN_HOME/.xprofile" 2>/dev/null; then
      cat >>"$MAIN_HOME/.xprofile" <<'XPROF'
# --- IM (fcitx5) ---
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
pgrep -x fcitx5 >/dev/null || fcitx5 -dr
XPROF
      chown "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.xprofile"
    fi
    su - "$MAIN_USER" -c 'im-config -n fcitx5 >/dev/null 2>&1 || true'
  fi
  ok "IME configured"

  # ---------- C. Polkit/LightDM ----------
  step "Polkit/LightDM tune"
  apt purge -y mate-polkit || true
  apt install -y xfce-polkit || true
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat >/etc/lightdm/lightdm.conf.d/50-gtk-greeter.conf <<'EOC'
[greeter]
font-name=Noto Sans 11
xft-hintstyle=hintfull
xft-antialias=true
xft-rgba=rgb
EOC
  ok "Greeter tuned"

  # ---------- D. Cmd-like shortcuts (xbindkeys 保険) ----------
  step "Setting up xbindkeys (Super+C/V → Ctrl+Shift+C/V as fallback)"
  if [ -n "$MAIN_HOME" ]; then
    install -d -m 0755 "$MAIN_HOME/.config/autostart" "$MAIN_HOME/.local/bin"
    cat >"$MAIN_HOME/.local/bin/_cmd_copy.sh" <<'SH'
#!/usr/bin/env bash
xdotool key --clearmodifiers ctrl+shift+c || xdotool key --clearmodifiers ctrl+c
SH
    cat >"$MAIN_HOME/.local/bin/_cmd_paste.sh" <<'SH'
#!/usr/bin/env bash
xdotool key --clearmodifiers ctrl+shift+v || xdotool key --clearmodifiers ctrl+v
SH
    chmod +x "$MAIN_HOME/.local/bin/"_cmd_*.sh
    chown -R "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.local"
    cat >"$MAIN_HOME/.xbindkeysrc" <<'XRC'
"~/.local/bin/_cmd_copy.sh"
  Super + c
"~/.local/bin/_cmd_paste.sh"
  Super + v
XRC
    chown "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.xbindkeysrc"
    cat >"$MAIN_HOME/.config/autostart/xbindkeys.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=xbindkeys
Exec=/usr/bin/xbindkeys
X-GNOME-Autostart-enabled=true
DESK
    chown -R "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.config"
  fi
  ok "xbindkeys configured"

  # ---------- E. VMware Shared folder helper ----------
  step "Installing mount-hgfs helper"
  cat >/usr/local/bin/mount-hgfs <<'HG'
#!/usr/bin/env bash
set -euo pipefail
MP="${1:-$HOME/Shared}"
mkdir -p "$MP"
if id -u | grep -qv '^0$'; then
  fusermount -u "$MP" >/dev/null 2>&1 || true
  vmhgfs-fuse -o allow_other,auto_unmount,uid=$(id -u),gid=$(id -g) .host:/ "$MP"
else
  umount "$MP" >/dev/null 2>&1 || true
  vmhgfs-fuse -o allow_other,auto_unmount .host:/ "$MP"
fi
echo "[+] mounted to $MP"
HG
  chmod +x /usr/local/bin/mount-hgfs
  ok "mount-hgfs ready"

  # ---------- F. XDG英語化 ----------
  step "Normalizing XDG user dirs (English)"
  if [ -n "$MAIN_HOME" ]; then
    install -d -o "$MAIN_USER" -g "$MAIN_USER" "$MAIN_HOME/.config"
    cat >"$MAIN_HOME/.config/user-dirs.dirs" <<'XDG'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
XDG_PROJECTS_DIR="$HOME/Projects"
XDG_NOTES_DIR="$HOME/Notes"
XDG_LOOT_DIR="$HOME/Loot"
XDG_LOGS_DIR="$HOME/Logs"
XDG_TOOLS_DIR="$HOME/Tools"
XDG
    chown "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.config/user-dirs.dirs"
    su - "$MAIN_USER" -c 'xdg-user-dirs-update'
    declare -A MAP=(
      ["デスクトップ"]="Desktop" ["ダウンロード"]="Downloads" ["テンプレート"]="Templates" ["公開"]="Public"
      ["ドキュメント"]="Documents" ["ミュージック"]="Music" ["画像"]="Pictures" ["ビデオ"]="Videos"
    )
    for jp in "${!MAP[@]}"; do
      en="${MAP[$jp]}"; [ -d "$MAIN_HOME/$jp" ] && [ ! -e "$MAIN_HOME/$en" ] && mv -n "$MAIN_HOME/$jp" "$MAIN_HOME/$en" || true
    done
    chown -R "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME"
  fi
  ok "XDG normalized"

  # ---------- G. initramfs safety ----------
  if [ "${SKIP_PLYMOUTH_DIVERT:-0}" != "1" ] && [ -d /usr/share/initramfs-tools/hooks ]; then
    step "Diverting plymouth hook to avoid update-initramfs failures"
    if [ -f /usr/share/initramfs-tools/hooks/plymouth ] && \
       ! dpkg-divert --list /usr/share/initramfs-tools/hooks/plymouth >/dev/null 2>&1; then
      dpkg-divert --package kali-bootstrap --add --rename \
        --divert /usr/share/initramfs-tools/hooks/plymouth.disabled \
        /usr/share/initramfs-tools/hooks/plymouth
      cat >/usr/share/initramfs-tools/hooks/plymouth <<'STUB'
#!/bin/sh
exit 0
STUB
      chmod +x /usr/share/initramfs-tools/hooks/plymouth
      update-initramfs -u || true
    fi
  fi
  ok "initramfs safety applied"

  # ---------- H. tmux 無効化 ----------
  step "Disabling tmux (remove + backup configs)"
  apt purge -y tmux 2>/dev/null || true
  for uhome in "/root" "$MAIN_HOME"; do
    [ -d "$uhome" ] || continue
    [ -f "$uhome/.tmux.conf" ] && mv -f "$uhome/.tmux.conf" "$uhome/.tmux.conf.bak.$(date +%s)"
    [ -d "$uhome/.tmux" ] && mv -f "$uhome/.tmux" "$uhome/.tmux.bak.$(date +%s)"
  done
  ok "tmux disabled"

  # ---------- I. WezTerm 設定投入（Ctrl+H / Ctrl+V 分割、CmdC/V） ----------
  step "Installing ~/.wezterm.lua for user ($MAIN_USER)"
  if [ -n "$MAIN_HOME" ]; then
    cat >"$MAIN_HOME/.wezterm.lua" <<'LUA'
-- ~/.wezterm.lua (Kali)
local wezterm = require 'wezterm'
local act = wezterm.action
local bg = os.getenv("WEZTERM_BG") or ""

return {
  font = wezterm.font_with_fallback({
    "JetBrains Mono", "FiraCode Nerd Font Mono", "DejaVu Sans Mono", "Noto Sans Mono CJK JP",
  }),
  font_size = 13.0,
  harfbuzz_features = { "liga=1", "clig=1", "calt=1" },

  color_scheme = "Tokyo Night Storm",
  hide_tab_bar_if_only_one_tab = true,
  use_fancy_tab_bar = true,
  enable_scroll_bar = false,
  window_decorations = "TITLE|RESIZE",     -- タイトルバー表示（最小化/最大化/クローズ）
  window_background_opacity = 0.92,
  text_background_opacity   = 1.0,
  inactive_pane_hsb = { saturation = 0.9, brightness = 0.55 },
  window_padding = { left = 6, right = 6, top = 6, bottom = 6 },

  window_background_image     = (bg ~= "" and bg or nil),
  window_background_image_hsb = (bg ~= "" and { brightness = 0.08, hue = 1.0, saturation = 1.0 } or nil),

  keys = {
    -- Copy/Paste
    -- { key = "c", mods = "SUPER",      action = act.CopyTo  "Clipboard" },
    -- { key = "v", mods = "SUPER",      action = act.PasteFrom "Clipboard" },
    { key = "c", mods = "CTRL", action = act.CopyTo  "Clipboard" },
    { key = "v", mods = "CTRL", action = act.PasteFrom "Clipboard" },

    -- Split: Ctrl+H (horizontal), Ctrl+V (vertical)  ← ご指定どおり
    { key = "h",         mods = "CTRL", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "Backspace", mods = "CTRL", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } }, -- ^H対策
    { key = "b",         mods = "CTRL", action = act.SplitVertical   { domain = "CurrentPaneDomain" } },

    -- Tabs
    { key = "t", mods = "SUPER", action = act.SpawnTab "CurrentPaneDomain" },
    { key = "w", mods = "SUPER", action = act.CloseCurrentTab { confirm = true } },
  },

  check_for_updates = false,
}
LUA
    chown "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.wezterm.lua"
  fi
  ok "~/.wezterm.lua installed"

  # ---------- J. proofshot ----------
  step "Installing proofshot command"
  cat >/usr/local/bin/proofshot <<'PFS'
#!/usr/bin/env bash
set -euo pipefail
usage(){ cat <<'USG'
Usage: proofshot [--full|--region|--window] [--outdir DIR] [--iface IF] [--label TEXT] [--file PATH]
USG
}
MODE="full"; OUTDIR="${XDG_SCREENSHOTS_DIR:-$HOME/Pictures/Screenshots}"; IFACE=""; LABEL=""; PFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --full) MODE="full"; shift;;
    --region) MODE="region"; shift;;
    --window) MODE="window"; shift;;
    --outdir) OUTDIR="${2:-}"; shift 2;;
    --iface) IFACE="${2:-}"; shift 2;;
    --label) LABEL="${2:-}"; shift 2;;
    --file)  PFILE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "[!] Unknown option: $1"; usage; exit 2;;
  esac
done
mkdir -p "$OUTDIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUTDIR/proof-$STAMP.png"
if [ -n "$IFACE" ]; then
  IP4="$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n1)"
else
  IP4="$(ip -4 -o addr | awk '!/ lo /{print $4}' | head -n1)"
fi
OVER="time: $(date -Iseconds)"; [ -n "$IP4" ] && OVER="$OVER | ip: $IP4"; [ -n "$LABEL" ] && OVER="$OVER | $LABEL"
if [ -n "$PFILE" ] && [ -r "$PFILE" ]; then CONTENT="$(tr -d '\r' < "$PFILE" | head -c 256)"; OVER="$OVER | $(basename "$PFILE"): $CONTENT"; fi
case "$MODE" in region) scrot -s "$OUT" ;; window) scrot -u "$OUT" ;; *) scrot "$OUT" ;; esac
if command -v convert >/dev/null 2>&1; then
  convert "$OUT" -gravity SouthEast -fill white -undercolor '#00000080' -pointsize 16 -annotate +10+10 "$OVER" "$OUT"
elif command -v magick >/dev/null 2>&1; then
  magick "$OUT" -gravity SouthEast -fill white -undercolor '#00000080' -pointsize 16 -annotate +10+10 "$OVER" "$OUT"
fi
echo "[+] saved: $OUT"
PFS
  chmod +x /usr/local/bin/proofshot
  ok "proofshot installed"

  echo; ok "Bootstrap complete."
  echo "  - Relogin recommended (IME/xbindkeys)"
  echo "  - WezTerm keys: Ctrl+C/V,  Ctrl+H (horizontal), Ctrl+B (vertical)"
}

main "$@"