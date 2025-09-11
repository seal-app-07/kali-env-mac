#!/usr/bin/env bash
# ==============================================================================
# kali-bootstrap.sh — Reproducible Kali-on-VM setup (GUI, tools, IME, Cmd shortcuts,
#                     Shared folder helper, tmux + plugins, OpenVPN helpers, proofshot)
#
# ■目的
#  - 最小インストールの Kali を、再現性高く“実用レディ”に仕上げる
#  - GUI/XFCE・日本語入力（fcitx5-mozc）
#  - 端末内の Cmd(Cmd+C / Cmd+V など) 風ショートカットを有効化
#  - VMware 共有フォルダを ~/Shared に簡単マウント
#  - 日本語名のホーム配下フォルダを英語名に正規化
#  - tmux をあなたの好み（prefix=C-a, vi-copy, **Ctrl-a h/v 分割**）+ 必須プラグイン込みで設定
#  - OpenVPN の up/down/ip ヘルパーを提供
#  - **proofshot** コマンドで OSCP 向けスクショを素早く作成
#  - initramfs 生成で躓きやすい plymouth hook を無害化（任意）
#
# ■OpenVPN ヘルパー
#   vpn-up  /path/to/profile.ovpn
#   vpn-down
#   vpn-ip
#   vpn-mtu 1250
#
# ■proofshot (新規)
#   proofshot [--full|--region|--window] [--outdir DIR] [--iface IF] [--label TEXT] [--file PATH]
#     例) proofshot --region --file ~/proof.txt --iface tun0 --label target-10.10.10.10
#
# ■注意
#  - 実行後は「再ログイン or 再起動」で xbindkeys/IME の自動起動が安定します。
#  - 本版では **Caps での IME 切替は無効**（Ctrl+Space のみ）。
# ==============================================================================

set -euo pipefail

# ---------- logging & helpers ----------
LOG="/var/log/kali-bootstrap.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
[ "${DEBUG:-0}" = "1" ] && set -x

trap 'echo "[!] Error (line $LINENO). See $LOG"' ERR
step(){ printf '\n\033[1;32m[STEP]\033[0m %s\n\n' "$*"; }
note(){ printf '\033[0;36m[i]\033[0m %s\n' "$*"; }
ok(){ printf '\033[0;32m[+]\033[0m %s\n' "$*"; }

require_root(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Run as root: sudo bash $0"
    exit 1
  fi
}

detect_main_user(){
  local u=
  u="${SUDO_USER:-}"
  if [ -z "$u" ] || [ "$u" = "root" ]; then
    u="$(logname 2>/dev/null || true)"
  fi
  if [ -z "$u" ] || [ "$u" = "root" ]; then
    u="$(awk -F: '$3==1000{print $1; exit}' /etc/passwd || true)"
  fi
  echo "$u"
}

# ----------------------------- main ------------------------------------------
main(){
  require_root

  MAIN_USER="$(detect_main_user)"
  MAIN_HOME=""
  if [ -n "$MAIN_USER" ] && [ "$MAIN_USER" != "root" ]; then
    MAIN_HOME="$(getent passwd "$MAIN_USER" | cut -d: -f6)"
  fi
  note "main user : ${MAIN_USER:-<none>}"
  note "main home : ${MAIN_HOME:-<n/a>}"

  export DEBIAN_FRONTEND=noninteractive

  # ---------- A. Base & Desktop ----------
  step "Updating APT & installing base utilities"
  apt update -qq
  apt install -y --no-install-recommends \
    ca-certificates curl wget gnupg git vim nano tmux \
    xclip xdg-user-dirs xdg-utils fonts-noto-cjk \
    xbindkeys xdotool \
    open-vm-tools-desktop \
    xfce4-terminal firefox-esr \
    resolvconf openvpn \
    scrot imagemagick


  step "Install VS Code (Deb822 .sources, normalized keyring)"
  install -d -m 0755 /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/microsoft.gpg ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
    chmod 0644 /etc/apt/keyrings/microsoft.gpg
  fi

  # 旧式や重複定義を掃除
  rm -f /etc/apt/sources.list.d/vscode.list 2>/dev/null || true
  sed -i -E 's#^(deb .*packages.microsoft.com/repos/code .*)#\# \1#g' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true

  # Deb822形式で正規化（毎回上書きOK）
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
  ok "VS Code installed (Deb822 .sources)"

  ok "Base packages installed (Firefox ESR, scrot, ImageMagick, VSCode included)"


  if [ "${SKIP_FULL:-0}" != "1" ]; then
    step "Installing Desktop & common Kali tools (kali-desktop-xfce, kali-linux-default)"
    apt install -y kali-desktop-xfce kali-linux-default
    ok "Desktop & default tools ready"
  else
    note "SKIP_FULL=1 => skipping kali-desktop-xfce/kali-linux-default"
  fi

  # ---------- B. Polkit agent ----------
  step "Ensuring single polkit agent (prefer XFCE)"
  apt purge -y mate-polkit || true
  apt install -y xfce-polkit || true

  # ---------- C. LightDM greeter tweaks ----------
  step "Configuring LightDM greeter (Noto Sans, anti-alias)"
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat >/etc/lightdm/lightdm.conf.d/50-gtk-greeter.conf <<'EOC'
[greeter]
font-name=Noto Sans 11
xft-hintstyle=hintfull
xft-antialias=true
xft-rgba=rgb
EOC
  ok "LightDM greeter tuned"

  # ---------- D. IME (fcitx5-mozc) & keyboard layout ----------
  step "Installing IME (fcitx5-mozc) and configuring keyboard"
  apt install -y --no-install-recommends fcitx5 fcitx5-mozc fcitx5-config-qt im-config

  LAYOUT="${LAYOUT:-}"
  if [ -z "$LAYOUT" ] && [ -f /etc/default/keyboard ]; then
    if grep -qi 'XKBLAYOUT=.*jp' /etc/default/keyboard; then
      LAYOUT="jis"
    else
      LAYOUT="us"
    fi
  fi
  [ -z "$LAYOUT" ] && LAYOUT="us"
  note "Detected layout: $LAYOUT (override with LAYOUT=us|jis)"

  if [ -n "$MAIN_HOME" ]; then
    install -d -m 0755 "$MAIN_HOME/.config" "$MAIN_HOME/.local/bin"
    # --- IME autostart in .xprofile ---
    if ! grep -q 'fcitx5 -dr' "$MAIN_HOME/.xprofile" 2>/dev/null; then
      cat >>"$MAIN_HOME/.xprofile" <<'XPROF'
# --- IM (fcitx5) ---
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
pgrep -x fcitx5 >/dev/null || fcitx5 -dr
XPROF
      chown "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.xprofile"
      chmod 0644 "$MAIN_HOME/.xprofile"
    fi
    sed -i '/xmodmap .*\.Xmodmap/d' "$MAIN_HOME/.xprofile" 2>/dev/null || true
    [ -f "$MAIN_HOME/.Xmodmap" ] && rm -f "$MAIN_HOME/.Xmodmap"
    su - "$MAIN_USER" -c 'im-config -n fcitx5 >/dev/null 2>&1 || true'
  fi
  ok "IME configured (Ctrl+Space only)"

  # ---------- E. Cmd-like shortcuts（xbindkeys） ----------
  step "Enabling Cmd-like shortcuts in terminals (Cmd→Ctrl(+Shift)/Alt mapping)"
  if [ -n "$MAIN_HOME" ]; then
    install -d -m 0755 "$MAIN_HOME/.config/autostart"
    install -d -m 0755 "$MAIN_HOME/.local/bin"
    cat >"$MAIN_HOME/.local/bin/_cmd_copy.sh" <<'SH'
#!/usr/bin/env bash
xdotool key --clearmodifiers ctrl+shift+c || xdotool key --clearmodifiers ctrl+c
SH
    cat >"$MAIN_HOME/.local/bin/_cmd_paste.sh" <<'SH'
#!/usr/bin/env bash
# Alt+v (tmux paste-buffer) → ダメなら Ctrl+Shift+v
xdotool key --clearmodifiers alt+v || xdotool key --clearmodifiers ctrl+shift+v
SH
    chmod +x "$MAIN_HOME/.local/bin/"_cmd_*.sh
    chown -R "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME/.local"

    cat >"$MAIN_HOME/.xbindkeysrc" <<'XRC'
# Cmd-like bindings (Super as macOS Command)
"~/.local/bin/_cmd_copy.sh"
  Super + c
"~/.local/bin/_cmd_paste.sh"
  Super + v
"xdotool key --clearmodifiers ctrl+a"
  Super + a
"xdotool key --clearmodifiers ctrl+x"
  Super + x
"xdotool key --clearmodifiers ctrl+z"
  Super + z
"xdotool key --clearmodifiers ctrl+y"
  Super + y
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
  ok "Cmd-like shortcuts enabled (relogin/reboot to activate)"

  # ---------- F. VMware Shared folder helper ----------
  step "Adding shared folder helper (vmhgfs-fuse -> ~/Shared)"
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
  ok "mount-hgfs ready (use: mount-hgfs)"

  # ---------- G. XDG English dirs & JP migration ----------
  step "Enforcing English XDG user directories and migrating JP folders"
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
      en="${MAP[$jp]}"
      if [ -d "$MAIN_HOME/$jp" ] && [ ! -e "$MAIN_HOME/$en" ]; then
        mv -n "$MAIN_HOME/$jp" "$MAIN_HOME/$en"
      fi
    done
    chown -R "$MAIN_USER":"$MAIN_USER" "$MAIN_HOME"
  fi
  ok "XDG dirs normalized"

  # ---------- H. initramfs safety (optional) ----------
  if [ "${SKIP_PLYMOUTH_DIVERT:-0}" != "1" ] && [ -d /usr/share/initramfs-tools/hooks ]; then
    step "Applying plymouth hook divert (prevent initramfs failures)"
    if [ -f /usr/share/initramfs-tools/hooks/plymouth ] && \
       ! dpkg-divert --list /usr/share/initramfs-tools/hooks/plymouth >/dev/null 2>&1; then
      dpkg-divert --package kali-bootstrap --add --rename \
        --divert /usr/share/initramfs-tools/hooks/plymouth.disabled \
        /usr/share/initramfs-tools/hooks/plymouth
      cat >/usr/share/initramfs-tools/hooks/plymouth <<'STUB'
#!/bin/sh
# diverted by kali-bootstrap; no-op to avoid failures during update-initramfs
exit 0
STUB
      chmod +x /usr/share/initramfs-tools/hooks/plymouth
      ok "plymouth hook diverted"
      update-initramfs -u || true
    else
      note "plymouth hook not present or already diverted; skipping"
    fi
  else
    note "SKIP_PLYMOUTH_DIVERT=1 -> skipping plymouth divert"
  fi

  # ---------- I. tmux（設定+プラグイン） ----------
  step "Configuring tmux (prefix C-a, vi-mode, clipboard, h/v split) & plugins"
  apt install -y --no-install-recommends git tmux xclip

  configure_tmux_for(){
    local user="$1" home="$2"

    install -d -m 0755 "$home/.tmux/plugins"
    chown -R "$user":"$user" "$home/.tmux"

    cat >"$home/.tmux.conf" <<"TMUXRC"
# ---------------------------------------------------------------------------- #
# basic
# ---------------------------------------------------------------------------- #
set -g mouse on
bind-key -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"
bind-key -n WheelDownPane select-pane -t= \; send-keys -M
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"

setw -g mode-keys vi

set -g prefix C-a
unbind C-b

set -g default-terminal "screen-256color"
set -g terminal-overrides 'xterm:colors=256'
setw -g status-style fg=colour255,bg=colour234

set -g base-index 1
set -g pane-base-index 1

bind r source-file ~/.tmux.conf \; display-message "$HOME/.tmux.conf reloaded!"
bind -T copy-mode-vi 'v' send-keys -X begin-selection

# ---------------------------------------------------------------------------- #
# clipboard & paste (robust on VMs)
# ---------------------------------------------------------------------------- #
set -g set-clipboard on

# copy-mode-vi: 'y' と 'Enter' でXクリップボードへ
unbind -T copy-mode-vi y
bind   -T copy-mode-vi y      send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"
bind   -T copy-mode-vi Enter  send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"

# mouse drag end -> クリップボードへ（再掲）
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"

# paste: Alt/Meta+v, Ctrl+Shift+V, Shift+Insert
bind -n M-v       paste-buffer
bind -n C-S-v     paste-buffer
bind -n S-Insert  paste-buffer

# paste: Ctrl+V（VMが Cmd+V→Ctrl+V に変換するケースを吸収）
bind -n C-v run-shell 'tmux set-buffer -- "$(xclip -o -selection clipboard 2>/dev/null || printf "")"; tmux paste-buffer'

# ---------------------------------------------------------------------------- #
# plugins
# ---------------------------------------------------------------------------- #
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-sidebar'
set -g @plugin 'tmux-plugins/tmux-pain-control'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @continuum-save-interval '10'

run '~/.tmux/plugins/tpm/tpm'

# ---------------------------------------------------------------------------- #
# custom bindings (AFTER plugins so our overrides take precedence)
# ---------------------------------------------------------------------------- #
unbind -T prefix h
bind   -T prefix h split-window -h
unbind -T prefix v
bind   -T prefix v split-window -v
TMUXRC
    chown "$user":"$user" "$home/.tmux.conf"

    # TPM bootstrap
    if [ ! -d "$home/.tmux/plugins/tpm/.git" ]; then
      sudo -u "$user" git clone --depth=1 https://github.com/tmux-plugins/tpm "$home/.tmux/plugins/tpm" || true
    fi
    sudo -u "$user" bash -lc '
      tmux -L __tpm_bootstrap__ start-server || true
      tmux -L __tpm_bootstrap__ new-session -d -s __tpm_bootstrap__ -n __dummy__ "sleep 1" || true
      ~/.tmux/plugins/tpm/bin/install_plugins || true
      tmux -L __tpm_bootstrap__ kill-session -t __tpm_bootstrap__ || true
    ' || true
  }

  configure_tmux_for root /root
  if [ -n "$MAIN_HOME" ]; then
    configure_tmux_for "$MAIN_USER" "$MAIN_HOME"
  fi
  ok "tmux configured (clipboard, Alt+v paste, C-a h/v split)"

  # ---------- J. OpenVPN helpers ----------
  step "Installing OpenVPN helpers (vpn-up/down/ip/mtu)"
  cat >/usr/local/bin/vpn-up <<'OVPNUP'
#!/usr/bin/env bash
set -euo pipefail
CFG="${1:-}"
[ -r "$CFG" ] || { echo "[!] Usage: vpn-up /path/to/profile.ovpn"; exit 2; }
PID="/run/kali-vpn.pid"
if [ -f "$PID" ] && ps -p "$(cat "$PID")" >/dev/null 2>&1; then
  echo "[i] Existing OpenVPN found. Stopping..."
  kill "$(cat "$PID")" || true; sleep 1
fi
OPTS=( --config "$CFG" --daemon ovpn-kali --writepid "$PID" --script-security 2 )
if [ -x /etc/openvpn/update-resolv-conf ]; then
  OPTS+=( --up /etc/openvpn/update-resolv-conf --down /etc/openvpn/update-resolv-conf )
fi
openvpn "${OPTS[@]}"
echo "[+] OpenVPN started (pid=$(cat "$PID"))"
for i in {1..20}; do ip -4 a s tun0 | grep -q 'inet ' && break; sleep 0.5; done
ip -4 a s tun0 || true
OVPNUP
  chmod +x /usr/local/bin/vpn-up

  cat >/usr/local/bin/vpn-down <<'OVPNDOWN'
#!/usr/bin/env bash
set -euo pipefail
PID="/run/kali-vpn.pid"
if [ -f "$PID" ] && ps -p "$(cat "$PID")" >/dev/null 2>&1; then
  kill "$(cat "$PID")" || true
  echo "[+] OpenVPN stopped"
else
  echo "[i] No OpenVPN daemon running"
fi
OVPNDOWN
  chmod +x /usr/local/bin/vpn-down

  cat >/usr/local/bin/vpn-ip <<'OVPNIP'
#!/usr/bin/env bash
ip -4 addr show tun0 2>/dev/null | awk '/inet /{print $2}'
OVPNIP
  chmod +x /usr/local/bin/vpn-ip

  cat >/usr/local/bin/vpn-mtu <<'OVPNMTU'
#!/usr/bin/env bash
set -euo pipefail
IF=${1:-tun0}; MTU=${2:-1250}
sudo ip link set dev "$IF" mtu "$MTU"
ip a s "$IF" | sed -n '1,3p'
echo "[+] set MTU $MTU on $IF"
OVPNMTU
  chmod +x /usr/local/bin/vpn-mtu
  ok "OpenVPN helpers installed"

  # ---------- K. proofshot ----------
  step "Installing proofshot command"
  cat >/usr/local/bin/proofshot <<'PFS'
#!/usr/bin/env bash
set -euo pipefail
usage(){
cat <<'USG'
Usage: proofshot [--full|--region|--window] [--outdir DIR] [--iface IFACE] [--label TEXT] [--file PATH]
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

  # ---------- L. Cleanup legacy ----------
  step "Cleaning up legacy tmux scripts (if any)"
  rm -f /usr/local/bin/*tmux*.sh || true

  # ---------- M. ~/.zshrc に自動追記（tmux自動起動 & BP無効化） ----------
  if [ -n "$MAIN_HOME" ]; then
    step "Injecting ~/.zshrc snippets (auto-tmux & disable bracketed paste)"
    ZSHRC="$MAIN_HOME/.zshrc"
    touch "$ZSHRC" && chown "$MAIN_USER":"$MAIN_USER" "$ZSHRC"

    su - "$MAIN_USER" -c "grep -q 'auto-start tmux safely' '$ZSHRC' || cat >>'$ZSHRC' <<'ZRC'
# --- [ZSH] auto-start tmux safely -------------------------------------------
if [ -n \"\$PS1\" ] && [ -z \"\$TMUX\" ] && [ -t 0 ]; then
  case \"\$TERM_PROGRAM\" in
    \"vscode\"|\"JetBrains\") : ;;
    *)
      if [ -z \"\$SSH_TTY\" ]; then
        TMUX_SESSION=\"\${TMUX_SESSION:-works}\"
        tmux has-session -t \"\$TMUX_SESSION\" 2>/dev/null && exec tmux attach -t \"\$TMUX_SESSION\"
        exec tmux new -s \"\$TMUX_SESSION\"
      fi
    ;;
  esac
fi

# --- [ZSH] disable terminal's bracketed paste mode --------------------------
disable_bracketed_paste() { printf '\e[?2004l'; }
autoload -Uz add-zsh-hook 2>/dev/null || true
add-zsh-hook precmd disable_bracketed_paste
add-zsh-hook preexec disable_bracketed_paste
zle -N bracketed-paste self-insert 2>/dev/null || true
ZRC"
    ok "~/.zshrc updated (auto tmux + BP off)"
  fi

  # ---------- N. 完了 ----------
  echo
  ok "Bootstrap complete."
  echo "  - Reboot or re-login recommended (IME/xbindkeys autostart)"
  echo "  - Logs: $LOG"
  echo "  - Shared folder: run 'mount-hgfs'  (default -> ~/Shared)"
  [ -n "$MAIN_USER" ] && echo "  - For $MAIN_USER: IME=fcitx5 (Ctrl+Space), Cmd-like shortcuts, tmux ready"
}

main "$@"