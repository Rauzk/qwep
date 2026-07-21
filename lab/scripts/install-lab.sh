#!/usr/bin/env bash
# 把实验配置装到系统 mosquitto（需要 sudo）
# 会备份旧 conf.d，并默认切入 01-insecure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
SYS_LAB="/etc/mosquitto/lab"
SYS_CONF_D="/etc/mosquitto/conf.d"
BACKUP_DIR="/etc/mosquitto/lab-backup-$(date +%Y%m%d-%H%M%S)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[!] 请用 sudo 运行: sudo $0"
  exit 1
fi

echo "[*] lab source: $ROOT"

# 证书与口令
bash "$SCRIPTS/gen-certs.sh" "$ROOT/certs"
bash "$SCRIPTS/gen-passwd.sh" "$ROOT/passwd/accounts.txt" "$ROOT/passwd/passwd"

# 系统目录
mkdir -p "$SYS_LAB"/{acl,certs,profiles}
install -m 640 "$ROOT/passwd/passwd" "$SYS_LAB/passwd"
chown root:mosquitto "$SYS_LAB/passwd" 2>/dev/null || chown root:root "$SYS_LAB/passwd"

install -m 644 "$ROOT/acl/"*.acl "$SYS_LAB/acl/"
install -m 644 "$ROOT/certs/ca.crt" "$SYS_LAB/certs/ca.crt"
install -m 644 "$ROOT/certs/server.crt" "$SYS_LAB/certs/server.crt"
install -m 640 "$ROOT/certs/server.key" "$SYS_LAB/certs/server.key"
chown root:mosquitto "$SYS_LAB/certs/server.key" 2>/dev/null || true
# 让 mosquitto 进程能读 key
chmod 640 "$SYS_LAB/certs/server.key"
# 若组不是 mosquitto，放宽到 644（仅 lab）
if ! id mosquitto &>/dev/null; then
  chmod 644 "$SYS_LAB/certs/server.key"
fi

install -m 644 "$ROOT/profiles/"*.conf "$SYS_LAB/profiles/"

# 备份并清空 conf.d 里旧 lab 配置
mkdir -p "$BACKUP_DIR"
if compgen -G "$SYS_CONF_D/*.conf" > /dev/null; then
  cp -a "$SYS_CONF_D/"*.conf "$BACKUP_DIR/" 2>/dev/null || true
fi
echo "[*] backup old conf.d -> $BACKUP_DIR"
# 去掉旧 insecure-lab 等，避免冲突
rm -f "$SYS_CONF_D/insecure-lab.conf" \
      "$SYS_CONF_D/mqtt-lab.conf" \
      "$SYS_CONF_D/00-mqtt-lab.conf"

# 主 mosquitto.conf 保持 include_dir 即可
if ! grep -q 'include_dir /etc/mosquitto/conf.d' /etc/mosquitto/mosquitto.conf; then
  echo "include_dir /etc/mosquitto/conf.d" >> /etc/mosquitto/mosquitto.conf
fi

# 默认 profile
PROFILE="${1:-01-insecure}"
bash "$SCRIPTS/switch-profile.sh" "$PROFILE"

# 客户端用 CA 副本（给普通用户读）
install -m 644 "$ROOT/certs/ca.crt" /etc/mosquitto/lab/certs/ca.crt
mkdir -p /usr/local/share/mqtt-lab
install -m 644 "$ROOT/certs/ca.crt" /usr/local/share/mqtt-lab/ca.crt

# 软链实验目录提示
ln -sfn "$ROOT" /opt/mqtt-lab-src 2>/dev/null || true

echo "[+] install done. active profile: $PROFILE"
echo "    switch: sudo $SCRIPTS/switch-profile.sh <01-insecure|02-auth-weak|03-acl-wide|04-acl-strict|05-tls-compare>"
echo "    seed:   $SCRIPTS/seed-retained.sh"
