#!/usr/bin/env bash
# 往 broker 种一批 retained 消息，方便主题遍历 / 伪造前后对比
set -euo pipefail

HOST="${MQTT_HOST:-192.168.2.127}"
PORT="${MQTT_PORT:-1883}"
USER="${MQTT_USER:-}"
PASS="${MQTT_PASS:-}"

auth=()
if [[ -n "$USER" ]]; then
  auth=(-u "$USER" -P "$PASS")
fi

pub() {
  local topic="$1" payload="$2"
  if mosquitto_pub -h "$HOST" -p "$PORT" "${auth[@]}" -t "$topic" -m "$payload" -r -q 1 2>/dev/null; then
    echo "  OK  $topic"
  else
    # 匿名失败则试 lab/lab
    if mosquitto_pub -h "$HOST" -p "$PORT" -u lab -P lab -t "$topic" -m "$payload" -r -q 1 2>/dev/null; then
      echo "  OK  $topic (as lab)"
    else
      echo "  FAIL $topic"
    fi
  fi
}

echo "[*] seed retained -> $HOST:$PORT"
pub "lab/insecure" "ready"
pub "lab/info" '{"lab":"mqtt-vuln","broker":"mosquitto","note":"authorized local only"}'
pub "home/device1/status" '{"online":true,"temp":26.5}'
pub "home/device1/cmd" '{"power":"off"}'
pub "sonoff/switch1/info" '{"password":"supersecret","fw":"1.0.0"}'
pub "owntracks/alice/phone" '{"_type":"location","lat":31.2304,"lon":121.4737}'
pub "factory/secret/token" "tok_abc123_do_not_leak"
pub "factory/status/line1" '{"ok":true,"rpm":1200}'
pub "factory/cmd/operator/reset" '{"action":"noop"}'
pub "lab/public" "anyone can read this under strict acl"

echo "[+] seed done"
echo "    检查: mosquitto_sub -h $HOST -p $PORT -t '#' -v -W 2"
