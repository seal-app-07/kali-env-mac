⸻

macOS の VM で Kali Linux を構築する（標準手順）

⚠️ このドキュメントは AI 支援で生成・加筆されています。
実環境へ適用する前に内容をご確認ください。再現手順は安定版 Kali Rollingを想定しています。

最小インストール → ブートストラップ一発で“通常利用できる Kali”を作ります。
US/JIS 配列、日本語 IME（fcitx5-mozc）、Cmd 風ショートカット、共有フォルダ、tmux、OpenVPN ヘルパー、スクショ支援（proofshot）までカバーします。

⸻

背景 / ねらい（Why）
	•	再現性：インストーラの選択肢に依存せず、最小から同じ手順で積み上げる
	•	VM あるある対策：配列差・IME・修飾キー差・共有フォルダなどを確実に整備
	•	壊れにくさ：initramfs × plymouth の既知不調を事前に無害化
	•	冪等性：何度流しても安全（存在チェック・追記最小）

⸻

必要要件
	•	macOS（Apple Silicon / Intel）
	•	ハイパーバイザ：VMware Fusion（Parallels / UTM でも概ね同様）
	•	Kali ISO（arm64/amd64）: https://www.kali.org/get-kali/

推奨 VM 設定：vCPU 2+ / RAM 4GB+ / Disk 40GB+ / NAT / 共有フォルダ有効

⸻

1) Kali を最小でインストール（Minimal）
	1.	新規 VM を作成して Kali ISO から起動
	2.	言語/配列は任意（後で IME/配列は再設定）
	3.	ソフトウェア選択は最小（デスクトップ等は外す）
	4.	再起動して通常ログイン

なぜ最小？
その後のブートストラップで GUI/ツールを同一手順で入れるため。
initramfs 周りの不調（plymouth）も回避しやすくなります。

⸻

2) ブートストラップの適用

VM への転送例（SSH を使う方法）：

# Kali 側（初回だけ）
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
ip -4 addr | awk '/inet / && $2 !~ /^127/ {print $2, $NF}'

# mac 側（例）
scp vm/kali/kali-bootstrap.sh  <kali-user>@<kali-ip>:~/

実行：

sudo DEBUG=1 ./kali-bootstrap.sh 2>&1 | tee /tmp/kali-bootstrap.log
# 完了後は再ログイン/再起動推奨

ログは /var/log/kali-bootstrap.log に保存。

⸻

3) スクリプトが行うこと（設計意図とコマンド解説）

方針：Kali 最小から「日常使いできるペンテスト環境」までを自動化。
破壊的変更は避け、可逆/上書え最小を徹底。

A. 基盤パッケージ導入（apt install ...）
	•	目的：最低限の CLI/GUI/入出力・ネットワーク・日本語表示・ブラウザを整える
	•	副作用：kali-desktop-xfce を入れると LightDM/各種 XFCE コンポーネントが大量に入る（後述）

B. Polkit の一本化
	•	apt purge mate-polkit → 重複 agent を除去
	•	apt install xfce-polkit → XFCE に合わせて 権限昇格 UI を統一

C. LightDM Greeter 調整
	•	/etc/lightdm/lightdm.conf.d/50-gtk-greeter.conf を生成
可読性（フォント/アンチエイリアス） を最低限整える

D. IME（fcitx5-mozc）
	•	im-config -n fcitx5 で 既定 IME を固定
	•	~/.xprofile に fcitx5 -dr 起動＋ GTK/QT_IM_MODULE, XMODIFIERS を設定
	•	Caps での IME 切替は無効（Kali 既定の Ctrl+Space のみ）
	•	旧版で配布した .Xmodmap 読み込み行やファイルは安全に撤去（将来衝突を防止）

E. Cmd 風ショートカット（端末内限定）
	•	xbindkeys + xdotool で Super（mac の Cmd） → Ctrl(+Shift) を送出
	•	対象：端末内のコピー/ペースト/選択/アンドゥ/リドゥ
	•	理屈：GUI アプリのショートカット衝突を避けるため、過剰なグローバル置換はしない
	•	自動起動：~/.config/autostart/xbindkeys.desktop

F. VMware 共有フォルダ（mount-hgfs）
	•	vmhgfs-fuse を使い .host:/ を $HOME/Shared にマウント
	•	ユーザ実行なら uid/gid を付与して書込権限を担保
	•	再実行に強いよう fusermount -u / umount を試行

G. XDG ユーザディレクトリの英語化
	•	~/.config/user-dirs.dirs を英語名で固定
	•	既存の日本語名フォルダ（例：ダウンロード）を移行
	•	xdg-user-dirs-update 実行で整合性をとる

H. initramfs × plymouth を無害化（可逆）
	•	背景：Minimal + GUI 追加後の update-initramfs が plymouth でコケる事例がある
	•	対策：dpkg-divert で /usr/share/initramfs-tools/hooks/plymouth を退避し、スタブ化
	•	影響：plymouth スプラッシュは使わない（一般的な VM 運用では問題なし）
	•	可逆性：dpkg-divert --remove でいつでも原状復帰可能

I. tmux（C-a プレフィクス、C-a h/v 分割、vi-copy、プラグイン）
	•	~/.tmux.conf を自動生成
	•	tmux-pain-control が h を先取りするため、プラグイン読み込み後に unbind → bind で確実に split-window -h/v
	•	TPM（tmux plugin manager）を非対話で導入（専用ソケットでノイズを分離）

J. OpenVPN ヘルパー（vpn-up/down/ip/mtu）
	•	daemon 起動＋PID 管理、update-resolv-conf があればDNS 連携
	•	vpn-ip で tun0 の IP を即確認、vpn-mtu で MTU 調整を簡略化

K. proofshot（証跡スクショ）
	•	scrot でキャプチャ → ImageMagick で 右下オーバーレイ（時刻/IP/任意ラベル/ファイル内容の先頭 256B）
	•	例：

proofshot --region --file ~/proof.txt --iface tun0 --label target-10.10.10.10



⸻

4) インストールされる全ツール一覧（このスクリプトが明示的に入れるもの）

注：「kali-linux-default / kali-desktop-xfce」はメタパッケージで膨大な依存がぶら下がります。
下の表はこのスクリプトが直接 apt install するパッケージを全件列挙しています（可読性のため機能要約を付与）。

パッケージ	用途 / 説明	なぜ必要か
ca-certificates	ルート証明書	TLS 通信の基本
curl / wget	HTTP(S) 取得	スクリプト/検証に必須
gnupg	署名検証	apt 鍵/アーカイブ検証
git	VCS	設定/プラグイン取得（TPM 等）
vim / nano	エディタ	最低限の編集環境
tmux	端末多重化	作業効率（C-a h/v 分割）
xclip	クリップボード連携	tmux yank / コピー連携
xdg-user-dirs / xdg-utils	XDG ディレクトリ/ユーティリティ	英語化/自動生成に使用
fonts-noto-cjk	CJK フォント	日本語表示
xbindkeys / xdotool	キーバインド送出	Cmd→Ctrl 変換
open-vm-tools-desktop	VMware 連携	共有フォルダ/連携強化
xfce4-terminal	端末	軽量ターミナル
firefox-esr	ブラウザ	既定ブラウザ
resolvconf	名前解決設定管理	OpenVPN と連携
openvpn	VPN クライアント	ラボ接続等
scrot	画面キャプチャ	proofshot の撮影
imagemagick	画像加工	proofshot のオーバーレイ
xfce-polkit	Polkit Agent	権限昇格 UI
fcitx5 / fcitx5-mozc / fcitx5-config-qt	日本語 IME	日本語入力
im-config	IM フレームワーク選択	fcitx5 を既定化
kali-desktop-xfce*	メタ（XFCE デスクトップ）	GUI 一式
kali-linux-default*	メタ（Kali 標準ツール）	代表的ペンテストツール群

* SKIP_FULL=1 なら入れません（ミニマム構成にしたい場合）。

スクリプトが生成/配置する独自コマンド

コマンド	役割
mount-hgfs	.host:/ を $HOME/Shared に FUSE マウント（VMware 共有）
vpn-up / vpn-down / vpn-ip / vpn-mtu	OpenVPN の起動/停止/IP表示/MTU調整を一括
proofshot	スクショ撮影＋右下オーバーレイ（時刻/IP/ラベル/ファイル先頭）


⸻

5) 「メタパッケージ」の実インストール内容を完全列挙する方法

バージョンで内容が変わるため、あなたのマシンで正解リストを生成するのが最も正確です。

# kali-desktop-xfce にぶら下がるパッケージ（推移依存を含む全展開）
apt-get update
apt-cache depends --recurse --no-suggests --no-recommends --no-conflicts \
  --no-breaks --no-replaces --no-enhances kali-desktop-xfce \
  | sed 's/.*>//' | sort -u > /tmp/kali-desktop-xfce.full.txt

# kali-linux-default も同様
apt-cache depends --recurse --no-suggests --no-recommends --no-conflicts \
  --no-breaks --no-replaces --no-enhances kali-linux-default \
  | sed 's/.*>//' | sort -u > /tmp/kali-linux-default.full.txt

# 説明付きの CSV へ（読みやすい資産化）
dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | awk -F, 'NR==FNR{a[$1];next} ($1 in a)' /tmp/kali-desktop-xfce.full.txt - \
  > ~/kali-desktop-xfce.inventory.csv

dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | awk -F, 'NR==FNR{a[$1];next} ($1 in a)' /tmp/kali-linux-default.full.txt - \
  > ~/kali-linux-default.inventory.csv

代表例（よく使うもの）
nmap, ffuf, feroxbuster, gobuster, seclists, sqlmap, hydra, john, hashcat,
impacket-*, crackmapexec（ローリングにより有無変動）, responder, smbclient,
metasploit-framework, bloodhound, neo4j, masscan, amass, httpx, naabu, など。
正確な一覧は上記の出力ファイルを参照してください。

⸻

6) よくある運用タスク

SSH サーバ（任意）

sudo apt install -y openssh-server
sudo systemctl enable --now ssh

proofshot 例

# 全画面/選択/アクティブウィンドウ
proofshot --full
proofshot --region
proofshot --window

# 右下に情報を出す（tun0 の IP とファイル内容先頭）
proofshot --region --iface tun0 --file ~/proof.txt --label "target 10.10.10.10"

tmux（C-a h / C-a v）

# 再読み込み
tmux source-file ~/.tmux.conf
# 水平 / 垂直分割（プラグインの割込みを回避して上書き済み）
# Prefix は Ctrl-a


⸻

7) トラブルシュート
	•	端末内のコピー/ペーストが効かない → pgrep -x xbindkeys || xbindkeys
	•	IME が効かない → im-config -n fcitx5 → 再ログイン / fcitx5-configtool
	•	共有フォルダが見えない → mount-hgfs（.host:/ が有効か確認）
	•	OpenVPN で DNS が切替わらない → /etc/openvpn/update-resolv-conf の有無確認
	•	initramfs 失敗 → dpkg-divert --list | grep plymouth を確認、必要なら update-initramfs -u
	•	tmux の h 分割が効かない → tmux list-keys -T prefix | grep split で上書きを確認

⸻

8) 設定ファイル・生成物の一覧
	•	~/.xprofile（fcitx5 起動・IM 環境変数）
	•	~/.xbindkeysrc（Cmd 風ショートカット） / ~/.config/autostart/xbindkeys.desktop
	•	~/.config/user-dirs.dirs（英語 XDG）
	•	~/.tmux.conf（C-a、h/v 分割、プラグイン） / ~/.tmux/plugins/tpm
	•	/usr/local/bin/mount-hgfs, proofshot, vpn-*
	•	/usr/share/initramfs-tools/hooks/plymouth（divert 済みスタブ）

⸻

9) アンインストール / ロールバックの考え方
	•	dpkg-divert --remove /usr/share/initramfs-tools/hooks/plymouth（plymouth 復帰）
	•	rm -f /usr/local/bin/{mount-hgfs,proofshot,vpn-*}（独自コマンド）
	•	sudo apt purge xbindkeys xdotool fcitx5 fcitx5-mozc など、目的別に段階的に削除
	•	~/.tmux.conf を削除 → tmux 既定に戻す

⸻

10) 開発者向けメモ（冪等性）
	•	ファイル生成は存在チェック→最小追記
	•	sed は具体行に限定（過剰置換を防止）
	•	dpkg-divert はidempotent（二重適用しない）
	•	プラグイン導入は専用ソケット（-L __tpm_bootstrap__）で静音化

⸻

付録：この README の「パッケージ一覧」を自動更新するワンライナー

README.md のメンテを簡単にするため、現在のインストール済みパッケージと説明を CSV 化：

dpkg-query -W -f='${Package},${Version},${binary:Summary}\n' \
  | sort -u > ~/installed-inventory-$(date +%Y%m%d).csv


⸻