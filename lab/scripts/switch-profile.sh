#!/usr/bin/env bash
# 切换 mosquitto 实验 profile（需要 root）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
SYS_LAB="/etc/mosquitto/lab"
SYS_CONF_D="/etc/mosquitto/conf.d"
ACTIVE="$SYS_CONF_D/00-mqtt-lab-active.conf"

usage() {
  echo "用法: sudo $0 <profile>"
  echo "可选:"
  ls -1 "$ROOT/profiles" 2>/dev/null | sed 's/^/  /;s/\.conf$//'
  echo
  echo "当前 active:"
  if [[ -L "$ACTIVE" || -f "$ACTIVE" ]]; then
    head -5 "$ACTIVE" 2>/dev/null | sed 's/^/  /'
    readlink -f "$ACTIVE" 2>/dev/null || true
  else
    echo "  (none)"
  fi
  exit 1
}

if [[ -z "$NAME" || "$NAME" == "-h" || "$NAME" == "--help" ]]; then
  usage
fi

# 允许写 01-insecure 或 01-insecure.conf
NAME="${NAME%.conf}"
SRC_SYS="$SYS_LAB/profiles/${NAME}.conf"
SRC_TREE="$ROOT/profiles/${NAME}.conf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[!] 需要 sudo"
  exit 1
fi

if [[ ! -f "$SRC_SYS" ]]; then
  if [[ -f "$SRC_TREE" ]]; then
    mkdir -p "$SYS_LAB/profiles"
    install -m 644 "$SRC_TREE" "$SRC_SYS"
  else
    echo "[!] 找不到 profile: $NAME"
    usage
  fi
fi

# 同步 tree -> system（改了源文件能立刻用）
install -m 644 "$SRC_TREE" "$SRC_SYS" 2>/dev/null || true
install -m 644 "$ROOT/acl/"*.acl "$SYS_LAB/acl/" 2>/dev/null || true

cp -f "$SRC_SYS" "$ACTIVE"
echo "$NAME" > "$SYS_LAB/ACTIVE_PROFILE"

# 确保 mosquitto 能读 key
if [[ -f "$SYS_LAB/certs/server.key" ]]; then
  chown root:mosquitto "$SYS_LAB/certs/server.key" 2>/dev/null || true
  chmod 640 "$SYS_LAB/certs/server.key" 2>/dev/null || chmod 644 "$SYS_LAB/certs/server.key"
fi
if [[ -f "$SYS_LAB/passwd" ]]; then
  chown root:mosquitto "$SYS_LAB/passwd" 2>/dev/null || true
  chmod 640 "$SYS_LAB/passwd"
fi

echo "[*] switching to $NAME"
# 干净重启，避免上次失败留下的手工 mosquitto 占端口
systemctl stop mosquitto 2>/dev/null || true
pkill -x mosquitto 2>/dev/null || true
sleep 0.4

if ! systemctl start mosquitto; then
  echo "[!] systemctl start failed，配置错误摘录："
  timeout 1 mosquitto -c /etc/mosquitto/mosquitto.conf -v 2>&1 | tail -40 || true
  journalctl -u mosquitto -n 20 --no-pager 2>/dev/null || true
  exit 1
fi
sleep 0.5
systemctl is-active mosquitto

echo "[+] active profile: $NAME"
ss -lntp 2>/dev/null | grep -E ':(1883|8883|9001)\b' || netstat -lntp 2>/dev/null | grep -E '1883|8883|9001' || true
echo "    tip: 换 profile 后若要演示业务数据，再跑 seed-retained.sh"
