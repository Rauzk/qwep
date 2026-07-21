#!/usr/bin/env bash
# 一眼看当前靶场状态
set -euo pipefail

HOST="${MQTT_HOST:-192.168.2.127}"

echo "=== MQTT Lab status ==="
echo "host: $HOST"
if [[ -f /etc/mosquitto/lab/ACTIVE_PROFILE ]]; then
  echo "profile: $(cat /etc/mosquitto/lab/ACTIVE_PROFILE)"
else
  echo "profile: (unknown — 先 install-lab.sh)"
fi
echo
echo "--- listeners ---"
ss -lntp 2>/dev/null | grep -E ':(1883|8883|9001)\b' || true
echo
echo "--- anon # (2s) ---"
timeout 2 mosquitto_sub -h "$HOST" -p 1883 -t '#' -v -W 1 2>&1 | head -20 || true
echo
echo "--- lab/lab # (2s) ---"
timeout 2 mosquitto_sub -h "$HOST" -p 1883 -u lab -P lab -t '#' -v -W 1 2>&1 | head -20 || true
echo
echo "--- tls 8883 (lab/lab, 2s) ---"
if [[ -f /usr/local/share/mqtt-lab/ca.crt ]]; then
  timeout 2 mosquitto_sub -h "$HOST" -p 8883 -u lab -P lab \
    --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/#' -v -W 1 2>&1 | head -10 || true
else
  echo "(no ca.crt installed)"
fi
echo
echo "=== done ==="
