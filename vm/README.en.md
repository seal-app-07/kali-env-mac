---

# Build Kali Linux on a macOS VM (Standard Playbook)

> ⚠️ This document was drafted/augmented with AI assistance.  
> Please review before applying to production. Steps assume the stable Kali Rolling release.

From a minimal install to a “daily-usable Kali” in one bootstrap run.  
Covers US/JIS layouts, Japanese IME (fcitx5-mozc), Cmd-like shortcuts, shared folders, tmux, OpenVPN helpers, and a screenshot helper (proofshot).

---

## Background / Goals (Why)

- **Reproducibility**: layer everything from minimal with the same steps, independent of installer choices
- **VM gotchas addressed**: keyboard layout, IME, modifier keys, shared folders—made reliable
- **Robustness**: proactively neutralize the known initramfs × plymouth failure path
- **Idempotency**: safe to re-run (existence checks / minimal edits)

---

## Prerequisites

- macOS (Apple Silicon / Intel)
- Hypervisor: VMware Fusion (Parallels / UTM are largely similar)
- Kali ISO (arm64/amd64): [https://www.kali.org/get-kali/](https://www.kali.org/get-kali/)

**Recommended VM settings**: vCPU 2+, RAM 4 GB+, Disk 40 GB+, NAT, Shared Folders enabled

---

## 1. Install Kali with the Minimal profile

1. Create a new VM and boot from the Kali ISO
2. Language / keyboard: anything (we’ll reconfigure IME/layout later)
3. Choose the minimal software set (uncheck desktop, etc.)
4. Reboot and log in as usual

> **Why minimal?**  
> So the bootstrap can add GUI/tools the same way every time.  
> It also avoids common plymouth/initramfs hiccups.

---

## 2. Apply the bootstrap

Example transfer via SSH:

```bash
# On Kali (first time only)
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
ip -4 addr | awk '/inet / && $2 !~ /^127/ {print $2, $NF}'

# On mac
scp vm/kali/kali-bootstrap.sh  <kali-user>@<kali-ip>:~/
```

Run it:

```bash
sudo DEBUG=1 ./kali-bootstrap.sh 2>&1 | tee /tmp/kali-bootstrap.log
# Re-login / reboot recommended afterwards
```

Logs are saved to `/var/log/kali-bootstrap.log`.

---

## 3. What the script does (design intent & command notes)

Strategy: automate from minimal Kali to a daily-usable pentest workstation.  
Avoid destructive changes; keep things reversible and minimally overriding.

### A. Base package install (apt install ...)
- Purpose: baseline CLI/GUI/I/O, networking, Japanese rendering, and a browser
- Side-effect: installing kali-desktop-xfce pulls in LightDM and many XFCE components (see below)

### B. Single polkit agent
- `apt purge mate-polkit` → remove duplicate agents
- `apt install xfce-polkit` → unify privilege escalation UI with XFCE

### C. LightDM Greeter tuning
- Generate `/etc/lightdm/lightdm.conf.d/50-gtk-greeter.conf` for basic readability (font/AA)

### D. IME (fcitx5-mozc)
- `im-config -n fcitx5` → pin fcitx5 as the default IM
- Add `fcitx5 -dr` to `~/.xprofile` and set `GTK_IM_MODULE`, `QT_IM_MODULE`, `XMODIFIERS`
- Caps-to-IME toggle is disabled; use Kali’s default Ctrl+Space
- Any legacy .Xmodmap hooks/files are safely removed to prevent future conflicts

### E. Cmd-like shortcuts (terminal-only)
- xbindkeys + xdotool to send Super (mac Cmd) → Ctrl(+Shift)
- Scope: terminal copy/paste/select/undo/redo
- Rationale: avoid global overrides that collide with GUI apps
- Autostart via `~/.config/autostart/xbindkeys.desktop`

### F. VMware Shared Folders (mount-hgfs)
- Use vmhgfs-fuse to mount `.host:/` → `$HOME/Shared`
- Preserve write permission for non-root (uid/gid)
- Robust re-runs (try fusermount -u / umount first)

### G. English XDG user dirs
- Pin `~/.config/user-dirs.dirs` to English names
- Migrate existing Japanese-named dirs (e.g., ダウンロード → Downloads)
- Run `xdg-user-dirs-update` for consistency

### H. Neutralize initramfs × plymouth (reversible)
- Context: adding GUI after minimal sometimes breaks update-initramfs via plymouth
- Fix: `dpkg-divert /usr/share/initramfs-tools/hooks/plymouth` to a stub
- Impact: plymouth splash is disabled (fine for typical VMs)
- Reversible: `dpkg-divert --remove` to restore

### I. tmux (C-a prefix, C-a h/v splits, vi-copy, plugins)
- Auto-generate `~/.tmux.conf`
- Because tmux-pain-control can grab h, we unbind+bind after plugins to guarantee split-window -h/-v
- TPM bootstrap is non-interactive (dedicated socket for quiet setup)

### J. OpenVPN helpers (vpn-up/down/ip/mtu)
- Run as a daemon with PID; use update-resolv-conf if present for DNS integration
- vpn-ip shows tun0 quickly; vpn-mtu simplifies MTU tuning

### K. proofshot (evidence screenshots)
- Capture via scrot, then ImageMagick overlays time/IP/custom label/first 256 B of a file in the lower-right
- Example:

```bash
proofshot --region --file ~/proof.txt --iface tun0 --label target-10.10.10.10
```

---

## 4. All tools this script installs explicitly

> Note: kali-linux-default and kali-desktop-xfce are meta-packages with large dependency trees.  
> The table below lists only the packages this script installs directly (with concise rationale).

| Package                        | Purpose / Description           | Why it’s needed            |
| ------------------------------ | ------------------------------ | -------------------------- |
| ca-certificates                | Root CAs                       | TLS basics                 |
| curl / wget                    | HTTP(S) fetch                  | Scripting / testing        |
| gnupg                          | Signature verification         | apt keys / archive checks  |
| git                            | VCS                            | Config & plugin fetch (TPM, etc.) |
| vim / nano                     | Editors                        | Minimal editing environment|
| tmux                           | Terminal multiplexer           | Productivity (C-a h/v splits) |
| xclip                          | Clipboard bridge               | tmux yank / copy integration|
| xdg-user-dirs / xdg-utils      | XDG dirs / utils               | English dirs / regeneration|
| fonts-noto-cjk                 | CJK fonts                      | Japanese rendering         |
| xbindkeys / xdotool            | Keybind injection              | Cmd→Ctrl mapping           |
| open-vm-tools-desktop          | VMware integration             | Shared folders / UX        |
| xfce4-terminal                 | Terminal                       | Lightweight terminal       |
| firefox-esr                    | Browser                        | Default browser            |
| resolvconf                     | Resolver management            | OpenVPN DNS integration    |
| openvpn                        | VPN client                     | Labs / remote networks     |
| scrot                          | Screen capture                 | proofshot capture          |
| imagemagick                    | Image processing               | proofshot overlay          |
| xfce-polkit                    | Polkit agent                   | Priv-esc UI                |
| fcitx5 / fcitx5-mozc / fcitx5-config-qt | Japanese IME           | JP input                   |
| im-config                      | IM framework selector          | Pin fcitx5                 |
| kali-desktop-xfce*             | Meta (XFCE desktop)            | Full GUI stack             |
| kali-linux-default*            | Meta (Kali defaults)           | Canonical pentest set      |

\* Omit with SKIP_FULL=1 for a lean setup.

### Script-provided helper commands

| Command                | Role                                                                   |
| ---------------------- | ---------------------------------------------------------------------- |
| mount-hgfs             | FUSE-mount .host:/ to $HOME/Shared (VMware shared folders)             |
| vpn-up / vpn-down / vpn-ip / vpn-mtu | Start/stop OpenVPN, show IP, tune MTU                    |
| proofshot              | Screenshot + lower-right overlay (time/IP/label/file head)             |

---

## 5. How to fully enumerate the actual contents of the meta-packages

The contents vary by release. The most accurate list is what your machine resolves right now:

```bash
# Everything (incl. transitive deps) under kali-desktop-xfce
apt-get update
apt-cache depends --recurse --no-suggests --no-recommends --no-conflicts \
  --no-breaks --no-replaces --no-enhances kali-desktop-xfce \
  | sed 's/.*>//' | sort -u > /tmp/kali-desktop-xfce.full.txt

# Same for kali-linux-default
apt-cache depends --recurse --no-suggests --no-recommends --no-conflicts \
  --no-breaks --no-replaces --no-enhances kali-linux-default \
  | sed 's/.*>//' | sort -u > /tmp/kali-linux-default.full.txt

# CSV with package, version, and summary
dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | awk -F, 'NR==FNR{a[$1];next} ($1 in a)' /tmp/kali-desktop-xfce.full.txt - \
  > ~/kali-desktop-xfce.inventory.csv

dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | awk -F, 'NR==FNR{a[$1];next} ($1 in a)' /tmp/kali-linux-default.full.txt - \
  > ~/kali-linux-default.inventory.csv
```

**Typical highlights** (subject to change by rolling release):  
`nmap, ffuf, feroxbuster, gobuster, seclists, sqlmap, hydra, john, hashcat, impacket-*, crackmapexec (may vary), responder, smbclient, metasploit-framework, bloodhound, neo4j, masscan, amass, httpx, naabu, etc.`  
For the authoritative list, see the generated CSVs above.

---

## 6. Common operational tasks

### SSH server (optional)

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

### proofshot examples

```bash
# Full / region / active window
proofshot --full
proofshot --region
proofshot --window

# Lower-right overlay with tun0 IP and head of a file
proofshot --region --iface tun0 --file ~/proof.txt --label "target 10.10.10.10"
```

### tmux (C-a h / C-a v)

```bash
# Reload config
tmux source-file ~/.tmux.conf
# Splits: Prefix is Ctrl-a; plugin override conflicts are already handled.
```

---

## 7. Troubleshooting

- Terminal copy/paste not working → `pgrep -x xbindkeys || xbindkeys`
- IME inactive → `im-config -n fcitx5`, re-login / `fcitx5-configtool`
- Shared folder invisible → `mount-hgfs` (ensure .host:/ is enabled)
- OpenVPN DNS not switching → check `/etc/openvpn/update-resolv-conf` existence
- initramfs failures → `dpkg-divert --list | grep plymouth`, then `update-initramfs -u` if needed
- tmux h split not working → `tmux list-keys -T prefix | grep split` to verify overrides

---

## 8. Files generated / changed

- `~/.xprofile` (fcitx5 autostart & IM env vars)
- `~/.xbindkeysrc` (Cmd-like shortcuts) / `~/.config/autostart/xbindkeys.desktop`
- `~/.config/user-dirs.dirs` (English XDG)
- `~/.tmux.conf` (C-a, h/v splits, plugins) / `~/.tmux/plugins/tpm`
- `/usr/local/bin/mount-hgfs, proofshot, vpn-*`
- `/usr/share/initramfs-tools/hooks/plymouth` (diverted stub)

---

## 9. Uninstall / rollback strategies

- Restore plymouth: `dpkg-divert --remove /usr/share/initramfs-tools/hooks/plymouth`
- Remove helpers: `rm -f /usr/local/bin/{mount-hgfs,proofshot,vpn-*}`
- Remove optional bits: `sudo apt purge xbindkeys xdotool fcitx5 fcitx5-mozc` (etc., as needed)
- Remove `~/.tmux.conf` to go back to stock tmux

---

## 10. Developer notes (Idempotency)

- Generate files with existence checks, use minimal edits
- Scope sed to specific lines (avoid over-matching)
- dpkg-divert is idempotent (no double-apply)
- Plugin bootstrap uses a dedicated tmux socket (`-L __tpm_bootstrap__`) to keep noise down

---

## Appendix: one-liner to refresh the “installed packages” inventory in this README

Produce a CSV of currently installed packages with summaries:

```bash
dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | sort -u > ~/installed-inventory-$(date +%Y%m%d).csv
```

---