#!/usr/bin/env bash
# 币润行情节点 · 部署公钥自动同步（一次安装，永久生效）
#
# 用法（腾讯云网页终端，root，每台节点只需执行一次）：
#   curl -fsSL <本脚本 raw 地址> | sudo bash
#   或把本文件内容粘贴到 /root/install-key-sync.sh 后：sudo bash /root/install-key-sync.sh
#
# 安装后：
# - 每 5 分钟从 KEYS_URL 拉取部署公钥列表，写入 /home/ubuntu/.ssh/authorized_keys 中的「托管区块」
#   （# >>> birun-key-sync … # <<< birun-key-sync 之间）；区块外你手动加的公钥一律不动、不删
# - 只接受形如 `ssh-ed25519 <key> birun-deploy-<名字>` 的行，最多 10 条；其它内容忽略
# - 拉取失败 / 内容为空 / 格式全不合法时保持现状（不会把自己锁在门外）
# - 沙盒重建后：只需把新公钥提交到 KEYS_URL 对应的文件，5 分钟内三台节点自动生效
#
# 卸载：sudo rm -f /etc/cron.d/birun-key-sync /usr/local/sbin/birun-key-sync
#       （托管区块里的公钥会保留，需要的话手动删除两行标记之间的内容）
set -euo pipefail

KEYS_URL="${KEYS_URL:-https://raw.githubusercontent.com/MAXHONG/birun-keys/main/authorized_keys}"
TARGET_USER="${TARGET_USER:-ubuntu}"
# 安装时立即写入的种子公钥（KEYS_URL 还没建好时也能马上登录）
SEED_KEYS="${SEED_KEYS:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHDSYo9gWgJ1fQ/3AD15EpVjuz3WWTrGrAYt8DN9Udvs birun-deploy-5}"

[ "$(id -u)" = 0 ] || { echo "请用 root 运行（sudo bash $0）" >&2; exit 1; }
id "$TARGET_USER" >/dev/null 2>&1 || { echo "用户 $TARGET_USER 不存在" >&2; exit 1; }

cat > /usr/local/sbin/birun-key-sync <<'SYNC'
#!/usr/bin/env bash
# 由 install-key-sync.sh 生成；用法：birun-key-sync [--seed "<公钥行>"]
set -euo pipefail
KEYS_URL="__KEYS_URL__"
TARGET_USER="__TARGET_USER__"
HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
AUTH="${AUTH_FILE:-$HOME_DIR/.ssh/authorized_keys}"
BEGIN='# >>> birun-key-sync (自动托管，勿手改此区块)'
END='# <<< birun-key-sync'
RE='^ssh-ed25519 [A-Za-z0-9+/]{68} birun-deploy-[A-Za-z0-9._-]{1,32}$'

src=""
if [ "${1:-}" = "--seed" ]; then
  src="${2:-}"
else
  src=$(curl -fsSL --max-time 15 --retry 2 "$KEYS_URL" 2>/dev/null) || { logger -t birun-key-sync "拉取失败，保持现状"; exit 0; }
fi

valid=$(printf '%s\n' "$src" | tr -d '\r' | sed 's/[[:space:]]\+$//' | grep -E "$RE" | awk '!seen[$0]++' | head -n 10 || true)
[ -n "$valid" ] || { logger -t birun-key-sync "没有合法公钥，保持现状"; exit 0; }

mkdir -p "$(dirname "$AUTH")"
touch "$AUTH"
# 区块外的内容原样保留
outside=$(awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$AUTH")
# --seed 模式：与现有区块合并（不覆盖已同步的公钥）
if [ "${1:-}" = "--seed" ]; then
  cur=$(awk -v b="$BEGIN" -v e="$END" '$0==b{on=1;next} $0==e{on=0;next} on' "$AUTH")
  valid=$(printf '%s\n%s\n' "$cur" "$valid" | grep -E "$RE" | awk '!seen[$0]++' | head -n 10)
fi

tmp=$(mktemp "$AUTH.XXXX")
{
  [ -n "$outside" ] && printf '%s\n' "$outside"
  printf '%s\n%s\n%s\n' "$BEGIN" "$valid" "$END"
} > "$tmp"
if cmp -s "$tmp" "$AUTH"; then rm -f "$tmp"; exit 0; fi
chmod 600 "$tmp"
mv -f "$tmp" "$AUTH"
chown -R "$TARGET_USER:$TARGET_USER" "$(dirname "$AUTH")"
chmod 700 "$(dirname "$AUTH")"
logger -t birun-key-sync "已更新：$(printf '%s\n' "$valid" | awk '{print $3}' | paste -sd, -)"
SYNC
sed -i "s#__KEYS_URL__#${KEYS_URL}#; s#__TARGET_USER__#${TARGET_USER}#" /usr/local/sbin/birun-key-sync
chmod 755 /usr/local/sbin/birun-key-sync

# 1) 立即写入种子公钥  2) 立即同步一次  3) 每 5 分钟同步
/usr/local/sbin/birun-key-sync --seed "$SEED_KEYS"
/usr/local/sbin/birun-key-sync || true
cat > /etc/cron.d/birun-key-sync <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/5 * * * * root /usr/local/sbin/birun-key-sync >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/birun-key-sync

echo "OK：已安装部署公钥自动同步（每 5 分钟，来源 $KEYS_URL）"
echo "当前托管公钥："
awk '/^# >>> birun-key-sync/{on=1;next} /^# <<< birun-key-sync/{on=0} on{print "  - "$3}' "$(getent passwd "$TARGET_USER" | cut -d: -f6)/.ssh/authorized_keys"
