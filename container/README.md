---

# コンテナ版 — Kali on macOS Virtualization.framework

> ⚠️ AI 生成/加筆ドキュメント  
> 本READMEとスクリプトはAI支援で作成されています。環境差（macOS/Virtualization.framework のバージョン、XQuartz、ネットワーク構成）や試験規約の変更による挙動の違いにご注意ください。運用前に必ず内容を確認してください。

用途: 軽量な日々の演習（HTB/THM など）。GUI は XQuartz + socat による X11 転送。  
VPN は ホスト（macOS）で接続 → pf/NAT でコンテナへ共有します。

---

## なぜ「コンテナ版」なのか（背景 / ねらい）

- **高速・軽量**: VM 起動より速く、スナップショット不要で使い捨てが簡単（ckali-clean）
- **整合性**: Kali 公式イメージをそのまま利用（docker.io/kalilinux/kali-rolling:latest）
- **制約回避**: Virtualization.framework では コンテナ内 TUN/TAP が難しいため、VPN はホストで貼り、pf NAT で共有する方針に統一
- **GUI 対応**: XQuartz の UNIX ソケットを socat で :6000/TCP にブリッジし、DISPLAY=<host>:0 で表示

🧭 **使い分け**  
- 演習/学習：本コンテナ版（軽快・再現容易）
- 試験本番/重ツール：VM 版（Kali 内で OpenVPN、カーネル機能やドライバが必要な場面に強い）

---

## 依存関係と前提

- macOS（Apple Silicon / Intel）
- Virtualization.framework の container CLI が使えること（`container --version` で確認）
- Homebrew が入っていること
- X11 表示用に XQuartz、ブリッジに socat

### 導入例

```sh
brew install --cask xquartz
brew install socat openvpn
# container ランタイムが停止中なら起動
container system start
```

---

## セットアップ（概要）

1. `container/zshrc` の内容を `~/.zshrc` に統合（既存と競合しないように）
2. Homebrew で xquartz, socat, openvpn を導入
3. 永続運用は `ckali`、毎回クリーンは `ckali-clean`、Burp は `burp-light`

---

## クイックスタート

```sh
# 1) X11 ブリッジを含む永続Kaliを起動
ckali

# 2) GUI テスト（コンテナ内）
xeyes  # or xclock

# 3) ホストで VPN を接続（OpenVPN など）
#    utunX ができる

# 4) コンテナ向けに VPN を共有
vpn-share-on

# 5) 逆向きシェルを受けるなら（デフォルト 1234/TCP）
nc -lvnp 1234   # コンテナ内
# ペイロード側 LHOST は utunX の inet（10.x.x.x）/ LPORT=1234

# 後片付け
vpn-share-off
```

---

## ディレクトリ/永続化の考え方

- `~/pentest/root` … 永続コンテナの `/root` にマウント（ワークスペース）
- **APT キャッシュ永続化（任意）**: 環境変数 `APT_PERSIST=1` で有効
    - `~/pentest/apt-cache` → `/var/cache/apt`
    - `~/pentest/apt-lists` → `/var/lib/apt/lists`

---

## .zshrc の設計（目的 / 背景 / 使い方）

以下は .zshrc に実装済みの関数/エイリアスを、目的/背景/使い方/安全面まで含めて解説します。

### 0) インタラクティブ時の安全 tmux attach

```sh
if [[ $- == *i* ]] && command -v tmux >/dev/null 2>&1; then
  if ! tmux has-session -t works 2>/dev/null; then
    tmux new -ds works
  fi
  [ -z "$TMUX" ] && tmux attach -t works
fi
```
- 目的：シェル起動時に自動で tmux へ入る（既存セッションがあれば attach）
- 安全性：非対話シェルでは無効。既に tmux 内なら何もしない。

### 1) PATH 設定

```sh
export PATH="$PATH:/opt/homebrew/opt/openvpn/sbin:/opt/X11/bin:/opt/homebrew/bin"
```
- 目的：Homebrew の OpenVPN、XQuartz の xhost 等を確実に見せる

### 2) 前回設定の掃除（冪等性）

```sh
# 既存の alias/関数をクリア
for a in ...; do unalias "$a" 2>/dev/null; done
unset -f ... 2>/dev/null
unset _tool_bootstrap 2>/dev/null
```
- 目的：.zshrc を再読み込みしても二重定義にならないようにする（冪等）

### 3) ホスト IP 解決 _host_ip

```sh
_host_ip() { ipconfig getifaddr en0 || ipconfig getifaddr en1 || printf "127.0.0.1"; }
```
- 目的：DISPLAY=<host_ip>:0 用にホストの LAN IP を簡易取得
- 補足：有線/無線により en0/en1 が異なるため、順に試行

### 4) X11 ブリッジ _x11_bridge_up / x11_up / x11_down

```sh
_x11_bridge_up() {
  # XQuartz 起動 → launchd の DISPLAY を取得 → :6000/TCP に socat でブリッジ
  # 最後に xhost + （誰でも接続可）を実施
}
x11_up(){ _x11_bridge_up; export DISPLAY="$(_host_ip):0"; }
x11_down(){ xhost - ; pkill -f 'socat TCP-LISTEN:6000' ; }
```
- 目的：XQuartz の UNIX ソケットを :6000/TCP に公開し、コンテナから GUI を表示
- 安全性：xhost + は緩いため、必要に応じて xhost +LOCAL: などに変更可
- テスト：xeyes / xclock（x11-apps をコンテナ側にインストール済み）

### 5) APT キャッシュ永続化 __apt_vols

- `APT_PERSIST=1` のとき、ホストの `~/pentest/apt-*` をマウント
    - 目的：apt update/upgrade の再実行負荷を軽減（演習を高速化）
    - 注意：書き込み権が無い場合は自動で無効化

### 6) コンテナ内ブートストラップ _tool_bootstrap

- 概要：Kali 内で一度だけ実行（`/root/.kali_bootstrapped` で判定）
- 主な処理：
    - 基本ツール：tmux, zsh, build-essential, python3, pipx, golang-go, jq, nmap, ffuf, feroxbuster, gobuster, seclists ほか
    - リコン/ウェブ：whatweb, wafw00f, nikto, sqlmap
    - SMB/AD：smbclient, smbmap, enum4linux-ng, python3-impacket, crackmapexec, ldap-utils, responder
    - 攻撃基盤：metasploit-framework, exploitdb, masscan, amass, proxychains4, chisel, sshuttle, mitmproxy
    - ネット：tcpdump, iproute2, dnsutils, netcat-traditional
    - GUI系：x11-apps, fonts-noto（X11 確認/日本語表示）
    - OpenJDK/JAR：openjdk-21-jre, burpsuite、保険で Temurin 21 リポジトリ追加＆ Burp JAR 直接取得
    - ネット復旧：`/usr/local/bin/net-repair` を配置（デフォルトGW/DNS の手動復旧用）
    - MTU 最適化：sysctl で PMTU 探索を有効化
    - Burp wrapper `burp-light`：Java のベスト候補を自動選択し、/mnt/burp-profile を HOME 代替に指定（設定の永続化を分離）

---

## コンテナ起動関数（ライフサイクル）

- **ckali（永続）**  
    - `/root` をホストに永続化して、日々の作業を継続
    - 初回だけ _tool_bootstrap が走る → 2回目以降はそのまま再利用
- **ckali-clean（クリーン）**  
    - 使い捨て実行。永続ボリュームは使わず、その場のみ
- **ckali-exec / ckali-rm**  
    - exec：既存 ckali-persist へ別タブで入る
    - rm：永続コンテナと ~/pentest/*（root, apt-cache/lists, burp-profile）を削除

---

## コンテナ情報取得ヘルパ

- `_kali_ip`：永続コンテナの eth0 IPv4 を取得（pf RDR の転送先に使用）
- `_vpn_utun`：ifconfig から 10.x アドレスを持つ utunX を検出（OpenVPN/Tunnelblick など）

---

## pf/NAT による VPN 共有

- **設計意図**  
    - Virtualization.framework のコンテナでは TUN/TAP が難しい → VPN はホストで接続
    - NAT + RDR により、「utunX →（NAT）→ コンテナ」「utunX:1234 → コンテナ:1234」を実現

- **ルール設計（順序が重要）**  
    - translation（rdr / nat）→ filtering（pass）の順で適用
    - Apple のアンカーを壊さないように、自前アンカー com.pentest.vpnshare を用意してそこだけ入れ替える

- **ベース適用 _ensure_pf_base**  
    - `set skip on lo0`
    - com.apple/* アンカーは維持
    - com.pentest.vpnshare アンカーを用意（ここに RDR/NAT/PASS を流し込む）

- **ON/OFF/RESET**
    - vpn-share-on：utun 検出 → Kali IP 取得 → rdr pass + nat + pass out をアンカーへ投入 → ip.forwarding=1
    - vpn-share-off：自分のアンカーだけを空にし、ベースへ戻す（pf は有効のまま）
    - vpn-share-reset：pf 全停止→デフォルト復旧（最終手段）

> 🔎 補足：README 内の例では pf-panic-reset に触れている箇所がありますが、実装は vpn-share-reset に統一されています（同等動作としてご利用ください）

- **便利関数**
    - vpn-share-status：現在の pfctl -sr/-sn とアンカー中身、ip.forwarding を一括表示
    - rshell-open：RDR を 1234/TCP で開けるショートカット（VPN_RPORT でポート変更可）
    - kali-set-mtu <MTU>：コンテナ内 eth0 の MTU を変更（VPN 越しの断続に有効）

---

## ヒント表示とランタイム起動

- 初回ロード時に使い方ヒントを表示（ZSHRC_KALI_HINT_SHOWN で二重抑止）
- container system start を呼び、ランタイムが落ちていても起こす

---

## 主要コマンド一覧（チートシート）

| コマンド         | 役割                      | 典型シーン                 |
|------------------|---------------------------|----------------------------|
| ckali            | 永続コンテナ起動/再開     | 日常の演習継続             |
| ckali-clean      | 使い捨てで起動            | 検証だけサクッと           |
| ckali-exec       | 既存永続へ別シェル attach | 並行作業                   |
| ckali-rm         | 永続環境の完全削除        | リセット                   |
| burp-light       | Burp を GUI 起動          | Web 解析                   |
| vpn-share-on     | utun NAT + RDR を適用     | VPN経由で到達性を確保      |
| vpn-share-off    | 自前アンカーだけ外す       | 一時停止                   |
| vpn-share-reset  | pf を完全初期化           | ルールが壊れた時の最終手段 |
| vpn-share-status | pf ルール/状態の一括確認  | デバッグ                   |
| kali-set-mtu     | MTU 調整                  | 断続/タイムアウト時         |

---

## セキュリティ考慮点

- **X11**: xhost + は広すぎるため、可能なら xhost +LOCAL: や特定IPに制限
- **pf ルール**: vpn-share-on の RDR は既定で 1234/TCP のみ（必要最小）
- **root 権限**: pfctl/sysctl は sudo を使う（パスワード入力が必要）
- **ネット復旧**: トラブル時は net-repair（コンテナ内）でデフォルトGW/DNS を一時復旧

---

## 典型ワークフロー例（HTB/THM）

1. ホストで VPN 接続（OpenVPN など）→ `ifconfig | grep utun` で utunX を確認
2. `ckali` → `xeyes` で GUI 表示を確認
3. `vpn-share-on` → コンテナから `curl ifconfig.io`（経路が変わるか確認）
4. 逆シェル受信：`nc -lvnp 1234`（コンテナ）／ペイロード LHOST=<utun inet> LPORT=1234
5. 終了後：`vpn-share-off` → `exit`（コンテナ）

---

## トラブルシュート

- GUI が出ない
    - XQuartz を起動（`open -a XQuartz`）、:6000 で socat LISTEN を確認
    - `lsof -n -iTCP:6000 -sTCP:LISTEN`
    - DISPLAY が `<host_ip>:0` か確認（`echo $DISPLAY`）

- コンテナから外に出られない
    - net-repair（コンテナ内）でデフォルトルート/DNS を復旧
    - kali-set-mtu 1400 などで MTU を調整

- VPN 共有が効かない
    - utunX 検出 → vpn-share-status で RDR/NAT 反映を確認
    - sysctl net.inet.ip.forwarding が 1 か
    - 競合する pf ルールがある場合は vpn-share-reset → 再適用

- 逆シェルが落ちる/詰まる
    - MTU を下げる（kali-set-mtu 1400）
    - LHOST は utunX の inet（10.x）を必ず指定

---

## 付録：_tool_bootstrap が入れる主なツール（用途要約）

- ビルド/言語：build-essential, python3（pipx/venv）, golang-go
- ユーティリティ：jq, unzip, xz-utils, file, tree, lsof, procps, net-tools, iproute2, dnsutils
- スキャナ/枚挙：nmap, masscan, amass, whatweb, wafw00f, nikto
- ディレクトリ系：gobuster, ffuf, feroxbuster, dirb, seclists, wordlists
- SMB/AD：smbclient, smbmap, enum4linux-ng, python3-impacket, ldap-utils, crackmapexec, responder
- 攻撃基盤：metasploit-framework, exploitdb, sqlmap, proxychains4, chisel, sshuttle, mitmproxy
- ネット：tcpdump, socat, openvpn, netcat-traditional, iputils-ping, inetutils-traceroute
- GUI：x11-apps, fonts-noto
- Burp/Java：burpsuite, openjdk-21-jre（保険で Temurin 21 も用意）

> バージョンや rolling により差異あり。正確な一覧は `dpkg -l` や `dpkg-query` で取得してください。

---

## メンテナンス / 片付け

- 永続環境の全削除：`ckali-rm`（コンテナ＆`~/pentest` の関連ディレクトリ）
- pf の完全復旧：`vpn-share-reset`（最終手段）

---

## よくある質問（FAQ）

- **Q. どうしてコンテナ内で OpenVPN しないの？**  
  A. Virtualization.framework のコンテナでは TUN/TAP が使えず、OpenVPN が安定しにくいため。ホストで VPN → pf 共有が安全確実。

- **Q. X11 をより安全に使いたい**  
  A. xhost +LOCAL: や xhost +<YourHostIP> に変更し、socat の bind アドレスを 127.0.0.1 に限定するなどを検討してください。

- **Q. RDR のポートを変えたい**  
  A. `VPN_RPORT=4444 vpn-share-on` のように環境変数で上書き可能です。

---

## 最後に（運用ポリシー）

- `.zshrc` は 冪等 かつ 可逆 を重視（何度読み込んでも壊れない）
- pf は 自前アンカーのみを操作し、Apple 既定アンカーは維持
- GUI 転送・VPN共有は 最小権限で（不要時は vpn-share-off / x11_down）

---