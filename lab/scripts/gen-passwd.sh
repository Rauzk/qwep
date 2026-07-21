#!/usr/bin/env bash
# 根据 accounts.txt 生成 mosquitto 口令文件
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNTS="${1:-$ROOT/passwd/accounts.txt}"
OUT="${2:-$ROOT/passwd/passwd}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

first=1
while read -r user pass; do
  [[ -z "${user:-}" || "$user" =~ ^# ]] && continue
  if [[ $first -eq 1 ]]; then
    mosquitto_passwd -b -c "$tmp" "$user" "$pass"
    first=0
  else
    mosquitto_passwd -b "$tmp" "$user" "$pass"
  fi
done < "$ACCOUNTS"

install -m 640 "$tmp" "$OUT"
echo "[+] wrote $OUT"
cut -d: -f1 "$OUT" | sed 's/^/  user: /'
