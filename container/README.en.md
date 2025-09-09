⸻

Container Edition — Kali on macOS Virtualization.framework

⚠️ About AI-generated content
This README and scripts were drafted/augmented with AI. Behavior may differ due to environment (macOS/Virtualization.framework, XQuartz, network layout) or exam policy changes. Review before use and proceed at your own risk. For exams (e.g., OSCP), follow official rules first.

Use case: lightweight daily labs (HTB/THM). GUI is X11 via XQuartz + socat.
VPN runs on the host (macOS) and is shared to the container via pf/NAT.

⸻

Why a “container edition”? (Background / Goals)
	•	Fast & lightweight: quicker than booting a full VM, no snapshots, easy throw-away runs (ckali-clean)
	•	Consistency: uses the official Kali image as-is (docker.io/kalilinux/kali-rolling:latest)
	•	Work around constraints: Virtualization.framework makes in-container TUN/TAP difficult → policy: run VPN on the host and share it via pf NAT
	•	GUI support: bridge the XQuartz UNIX socket to :6000/TCP with socat, then DISPLAY=<host>:0

🧭 When to use which
	•	Practice / learning: this container edition (snappy, reproducible)
	•	Exams / heavy tooling: the VM edition (OpenVPN runs inside Kali; better for kernel/driver needs)

⸻

Requirements & Assumptions
	•	macOS (Apple Silicon / Intel)
	•	The Virtualization.framework container CLI is available (container --version)
	•	Homebrew installed
	•	XQuartz for X11 display, socat for bridging

Install (example)

brew install --cask xquartz
brew install socat openvpn
# Start the container runtime if it’s not running
container system start


⸻

Setup (Overview)
	1.	Merge container/zshrc into your ~/.zshrc (avoid clobbering existing settings)
	2.	Install xquartz, socat, openvpn via Homebrew
	3.	Use ckali for persistent usage, ckali-clean for clean runs, and burp-light for Burp GUI

⸻

Quick Start

# 1) Launch persistent Kali (with X11 bridge)
ckali

# 2) Test GUI (inside the container)
xeyes  # or xclock

# 3) Connect VPN on the host (OpenVPN, etc.)
#    You should see a utunX interface

# 4) Share the VPN to the container
vpn-share-on

# 5) Receive a reverse shell (default 1234/TCP)
nc -lvnp 1234   # inside the container
# Payload LHOST = your utunX inet (10.x.x.x), LPORT=1234

# Cleanup
vpn-share-off


⸻

Directories & Persistence
	•	~/pentest/root → mounts to the container’s /root (your workspace)
	•	Optional APT cache persistence: enable with APT_PERSIST=1
	•	~/pentest/apt-cache → /var/cache/apt
	•	~/pentest/apt-lists → /var/lib/apt/lists

⸻

What’s in .zshrc (Design / Rationale / Usage)

This documents each function/alias shipped in .zshrc — with purpose, background, usage, and safety.
You can trace what each line is trying to achieve directly from the README.

0) Safe tmux attach (interactive shells only)

if [[ $- == *i* ]] && command -v tmux >/dev/null 2>&1; then
  if ! tmux has-session -t works 2>/dev/null; then
    tmux new -ds works
  fi
  [ -z "$TMUX" ] && tmux attach -t works
fi

	•	Purpose: auto-attach to tmux on interactive shell start (reuse works if it exists)
	•	Safety: no effect in non-interactive shells; does nothing if already inside tmux

⸻

1) PATH

export PATH="$PATH:/opt/homebrew/opt/openvpn/sbin:/opt/X11/bin:/opt/homebrew/bin"

	•	Purpose: ensure Homebrew’s OpenVPN and XQuartz tools (e.g., xhost) are on PATH

⸻

2) Cleanup for idempotency

# Clear existing aliases/functions so re-sourcing doesn’t double-define
for a in ...; do unalias "$a" 2>/dev/null; done
unset -f ... 2>/dev/null
unset _tool_bootstrap 2>/dev/null

	•	Purpose: make .zshrc safe to re-load repeatedly without stacking definitions

⸻

3) Host IP resolver: _host_ip

_host_ip() { ipconfig getifaddr en0 || ipconfig getifaddr en1 || printf "127.0.0.1"; }

	•	Purpose: quickly get the host LAN IP for DISPLAY=<host_ip>:0
	•	Note: tries en0 then en1 (wired vs Wi-Fi differs by machine)

⸻

4) X11 bridge: _x11_bridge_up / x11_up / x11_down

_x11_bridge_up() {
  # Start XQuartz → read launchd DISPLAY → bridge to :6000/TCP with socat
  # Finally run: xhost +   (allow all; consider tightening)
}
x11_up(){ _x11_bridge_up; export DISPLAY="$(_host_ip):0"; }
x11_down(){ xhost - ; pkill -f 'socat TCP-LISTEN:6000' ; }

	•	Purpose: expose XQuartz’s UNIX socket on :6000/TCP so the container can draw GUI
	•	Security: xhost + is permissive; prefer xhost +LOCAL: or a specific host if possible
	•	Testing: xeyes / xclock (installed in the container via x11-apps)

⸻

5) APT cache persistence: __apt_vols
	•	Purpose: reduce apt update/upgrade time across runs
	•	Behavior: when APT_PERSIST=1, mount ~/pentest/apt-* to apt cache/list paths; auto-disables if unwritable

⸻

6) In-container bootstrap: _tool_bootstrap
	•	Runs once per container (/root/.kali_bootstrapped flag)
	•	Installs (high-level):
	•	Core tooling: tmux, zsh, build-essential, python3 (+ venv, pipx), golang-go, jq
	•	Recon/Web: whatweb, wafw00f, nikto, sqlmap
	•	Wordlists/dirs: seclists, wordlists, gobuster, ffuf, feroxbuster, dirb
	•	Network: nmap, masscan, amass, proxychains4, tcpdump, iproute2, dnsutils, netcat-traditional, socat, openvpn
	•	SMB/AD: smbclient, smbmap, enum4linux-ng, python3-impacket, ldap-utils, crackmapexec, responder
	•	Attack frameworks: metasploit-framework, exploitdb, sshuttle, chisel, mitmproxy
	•	GUI sanity: x11-apps, fonts-noto (for Japanese rendering)
	•	Java/Burp: openjdk-21-jre, burpsuite; also adds Temurin 21 repo as fallback and fetches the Burp community JAR if needed
	•	Network repair: /usr/local/bin/net-repair to restore default route/DNS manually
	•	MTU/PMTU tweaks: enable PMTU probing to avoid VPN-path stalls
	•	burp-light wrapper: auto-selects a working Java and runs Burp with HOME redirected to /mnt/burp-profile so your settings are persisted separately.

⸻

7) Container lifecycle functions

ckali (persistent)

ckali_fn(){ ... container run -it --name ckali-persist \
  --env DISPLAY="$DISPLAY" --env XAUTHORITY="/dev/null" \
  --volume "$HOME/pentest/root:/root" --volume "$HOME:/mnt" \
  --workdir /root $(__apt_vols) \
  docker.io/kalilinux/kali-rolling:latest bash -lc "$_tool_bootstrap" }
alias ckali='ckali_fn'

	•	Purpose: keep /root on the host for day-to-day continuity
	•	Behavior: _tool_bootstrap runs only the first time; subsequent runs reuse the environment

ckali-clean (throw-away)

ckali_clean_fn(){ ... container run --rm -it ... kali-rolling bash -lc "$_tool_bootstrap" }
alias ckali-clean='ckali_clean_fn'

	•	Purpose: ephemeral runs; no persistent volumes

ckali-exec / ckali-rm
	•	exec: open another shell into the existing ckali-persist
	•	rm: remove ckali-persist and clean ~/pentest/{root,apt-cache,apt-lists,burp-profile}

⸻

8) Helper info functions
	•	_kali_ip: fetch IPv4 of the container’s eth0 (used as RDR destination)
	•	_vpn_utun: detect the host utunX that has a 10.x.* address (OpenVPN/Tunnelblick)

⸻

9) VPN sharing via pf/NAT

Design intent
	•	Containers on Virtualization.framework can’t reliably use TUN/TAP → run VPN on the host
	•	Use NAT + RDR to achieve both utunX → (NAT) → container and utunX:1234 → container:1234

Rule ordering matters
	•	Apply translation (rdr, nat) before filtering (pass)
	•	Do not disturb Apple’s anchors; use our own anchor com.pentest.vpnshare and only swap rules there

Base setup: _ensure_pf_base
	•	set skip on lo0
	•	Keep com.apple/* anchors
	•	Create empty com.pentest.vpnshare anchors (we load rules into this anchor)

ON/OFF/RESET
	•	vpn-share-on: detect utun, get Kali IP, load rdr pass + nat + pass out into our anchor, then enable net.inet.ip.forwarding=1
	•	vpn-share-off: clear only our anchor and restore the base (pf remains enabled)
	•	vpn-share-reset: disable pf and restore defaults (last resort)

🔎 Note: if you see pf-panic-reset referenced elsewhere, the implementation is unified as vpn-share-reset here (equivalent behavior).

Convenience
	•	vpn-share-status: show pfctl -sr/-sn, our anchor’s rules, and ip.forwarding
	•	rshell-open: quick RDR for TCP/1234 (override with VPN_RPORT)
	•	kali-set-mtu <MTU>: set container eth0 MTU (helps with VPN path issues)

⸻

10) Hints & runtime startup
	•	Show a one-time usage hint on first load (ZSHRC_KALI_HINT_SHOWN prevents repeats)
	•	Run container system start so the runtime is up even if it was down

⸻

Command Cheat Sheet

Command	Role	Typical use
ckali	Start/resume persistent container (GUI capable)	Ongoing practice
ckali-clean	Start a throw-away container	Quick tests
ckali-exec	Attach another shell to the persistent container	Parallel work
ckali-rm	Remove persistent environment & related dirs	Full reset
burp-light	Launch Burp GUI (XQuartz)	Web analysis
vpn-share-on	Apply utun NAT + RDR	Reach targets via VPN
vpn-share-off	Remove only our anchor rules	Pause sharing
vpn-share-reset	Fully reset pf	Last resort
vpn-share-status	Inspect pf rules/state	Debugging
kali-set-mtu 1400	Tune MTU	Drops/timeouts


⸻

Security Considerations
	•	X11: xhost + is too permissive; prefer xhost +LOCAL: or xhost +<YourHostIP>. You can also bind socat to 127.0.0.1 only.
	•	pf rules: vpn-share-on exposes TCP/1234 by default (minimum necessary); adjust via VPN_RPORT.
	•	Root privileges: pfctl / sysctl require sudo.
	•	Network repair: use net-repair (inside the container) to restore default GW/DNS if needed.

⸻

Typical HTB/THM Workflow
	1.	Connect VPN on the host (OpenVPN, etc.) → confirm utunX with ifconfig | grep utun
	2.	ckali → verify GUI with xeyes
	3.	vpn-share-on → from the container run curl ifconfig.io to verify the route
	4.	Reverse shell: nc -lvnp 1234 (container) / payload LHOST=<utun inet> LPORT=1234
	5.	When done: vpn-share-off → exit (container)

⸻

Troubleshooting
	•	No GUI appears
	•	Start XQuartz (open -a XQuartz), confirm socat listening on :6000:

lsof -n -iTCP:6000 -sTCP:LISTEN


	•	Ensure DISPLAY is <host_ip>:0 (echo $DISPLAY)

	•	No Internet from the container
	•	Run net-repair inside the container to restore default route/DNS
	•	Try MTU tuning: kali-set-mtu 1400
	•	VPN sharing not working
	•	Confirm utunX detection; run vpn-share-status to see RDR/NAT loaded
	•	Check sysctl net.inet.ip.forwarding equals 1
	•	If rules conflict, vpn-share-reset → re-apply
	•	Reverse shell drops/stalls
	•	Lower MTU (kali-set-mtu 1400)
	•	Ensure LHOST is the utunX inet (10.x)

⸻

Appendix: Major tools installed by _tool_bootstrap (purpose summary)
	•	Build/lang: build-essential, python3 (pipx/venv), golang-go
	•	Utils: jq, unzip, xz-utils, file, tree, lsof, procps, net-tools, iproute2, dnsutils
	•	Scanning/enum: nmap, masscan, amass, whatweb, wafw00f, nikto
	•	Dir brute/wordlists: gobuster, ffuf, feroxbuster, dirb, seclists, wordlists
	•	SMB/AD: smbclient, smbmap, enum4linux-ng, python3-impacket, ldap-utils, crackmapexec, responder
	•	Attack frameworks: metasploit-framework, exploitdb, sqlmap, proxychains4, chisel, sshuttle, mitmproxy
	•	Network: tcpdump, socat, openvpn, netcat-traditional, iputils-ping, inetutils-traceroute
	•	GUI: x11-apps, fonts-noto
	•	Burp/Java: burpsuite, openjdk-21-jre (Temurin 21 as fallback)

Rolling releases may vary. For an authoritative list, use dpkg -l / dpkg-query.

⸻

Maintenance / Cleanup
	•	Remove everything persistent: ckali-rm (container + ~/pentest directories)
	•	Fully restore pf: vpn-share-reset (last resort)

⸻

FAQ
	•	Q. Why not run OpenVPN inside the container?
A. Virtualization.framework containers don’t reliably support TUN/TAP, so OpenVPN is unstable there. Running VPN on the host and sharing via pf is safer and simpler.
	•	Q. How do I harden X11?
A. Use xhost +LOCAL: or xhost +<YourHostIP>, and bind socat to 127.0.0.1 only.
	•	Q. Change the RDR port?
A. Use an env var: VPN_RPORT=4444 vpn-share-on.

⸻

Operations Policy
	•	.zshrc prioritizes idempotency and reversibility (safe to re-source anytime)
	•	pf operations touch only our own anchor; Apple default anchors remain intact
	•	Keep GUI forwarding & VPN sharing at least privilege (turn off with vpn-share-off / x11_down when not needed)

⸻
