#!/usr/bin/env bash
# 发表级关键图补拍：只在 DISPLAY=:99，不碰 GNOME 前台
# 目标：05 明文抓包 / 07 伪造 / 10 QoS / 11 明文对照 / 12 TLS 对照
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="$ROOT/lab"
SHOTS="$ROOT/shots"
HOST="${MQTT_HOST:-192.168.2.127}"
export DISPLAY="${DISPLAY:-:99}"
WIN="mqtt-lab:0"

mkdir -p "$SHOTS" "$LAB/pcap"

need_display() { xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; }
if ! need_display; then
  echo "[!] DISPLAY $DISPLAY 不可用（应是 Xvfb :99）"
  exit 1
fi
tmux has-session -t mqtt-lab 2>/dev/null || { echo "[!] 无 mqtt-lab tmux"; exit 1; }

shot() {
  local name="$1"
  sleep "${2:-0.9}"
  rm -f "$SHOTS/${name}.png" "$SHOTS/${name}_"*.png 2>/dev/null || true
  scrot -D "$DISPLAY" "$SHOTS/${name}.png"
  if [[ ! -f "$SHOTS/${name}.png" ]]; then
    local alt; alt=$(ls -1t "$SHOTS/${name}"_*.png 2>/dev/null | head -1 || true)
    [[ -n "${alt:-}" ]] && mv -f "$alt" "$SHOTS/${name}.png"
  fi
  echo "[shot] ${name}.png ($(stat -c%s "$SHOTS/${name}.png") bytes)"
}

clearp() {
  tmux send-keys -t "$WIN.$1" C-c 2>/dev/null || true
  sleep 0.12
  tmux send-keys -t "$WIN.$1" "clear" Enter
  sleep 0.12
}
run0() { clearp 0; tmux send-keys -t "$WIN.0" "$*" Enter; }
run1() { clearp 1; tmux send-keys -t "$WIN.1" "$*" Enter; }
run2() { clearp 2; tmux send-keys -t "$WIN.2" "$*" Enter; }

switch() {
  sudo bash "$LAB/scripts/switch-profile.sh" "$1" >/tmp/mqtt-switch.log 2>&1
  sleep 0.5
}
seed() {
  if [[ $# -ge 2 ]]; then
    MQTT_USER="$1" MQTT_PASS="$2" bash "$LAB/scripts/seed-retained.sh" >/tmp/mqtt-seed.log 2>&1
  else
    bash "$LAB/scripts/seed-retained.sh" >/tmp/mqtt-seed.log 2>&1
  fi
}

# 先在后台把 pcap 准备好，终端只负责「展示结果」（避免超时拍到空屏）
prepare_pcaps() {
  echo "[*] prepare pcaps offline..."
  switch 01-insecure
  seed

  # --- plain 1883 with auth ---
  sudo timeout 5 tcpdump -i any -n -s 0 -w "$LAB/pcap/plain-1883.pcap" 'tcp port 1883' >/tmp/td-plain.log 2>&1 &
  local tp=$!
  sleep 0.9
  mosquitto_pub -h "$HOST" -p 1883 -u lab -P 'lab' -t 'lab/demo' -m 'hello-plain-mqtt'
  mosquitto_sub -h "$HOST" -p 1883 -u lab -P 'lab' -t 'lab/demo' -C 1 -W 2 >/dev/null 2>&1 || true
  sleep 2
  wait $tp 2>/dev/null || true

  # --- qos ---
  sudo timeout 5 tcpdump -i any -n -s 0 -w "$LAB/pcap/qos-1883.pcap" 'tcp port 1883' >/tmp/td-qos.log 2>&1 &
  tp=$!
  sleep 0.9
  mosquitto_pub -h "$HOST" -p 1883 -t 'lab/qos' -q 0 -m 'q0-at-most-once'
  mosquitto_pub -h "$HOST" -p 1883 -t 'lab/qos' -q 1 -m 'q1-at-least-once'
  mosquitto_pub -h "$HOST" -p 1883 -t 'lab/qos' -q 2 -m 'q2-exactly-once'
  sleep 2
  wait $tp 2>/dev/null || true

  # --- tls compare ---
  switch 05-tls-compare
  # plain side under tls profile (strict acl: lab can write lab/user/#)
  sudo timeout 5 tcpdump -i any -n -s 0 -w "$LAB/pcap/compare-plain.pcap" 'tcp port 1883' >/tmp/td-cp.log 2>&1 &
  tp=$!
  sleep 0.9
  mosquitto_pub -h "$HOST" -p 1883 -u lab -P lab -t 'lab/user/hello' -m 'this-is-plain'
  sleep 2
  wait $tp 2>/dev/null || true

  sudo timeout 6 tcpdump -i any -n -s 0 -w "$LAB/pcap/compare-tls.pcap" 'tcp port 8883' >/tmp/td-ct.log 2>&1 &
  tp=$!
  sleep 0.9
  mosquitto_pub -h "$HOST" -p 8883 -u lab -P lab \
    --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/user/hello' -m 'this-is-tls'
  mosquitto_sub -h "$HOST" -p 8883 -u lab -P lab \
    --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/user/hello' -C 1 -W 2 >/dev/null 2>&1 || true
  sleep 2.5
  wait $tp 2>/dev/null || true

  # write small summary files for display
  {
    echo '=== tshark: MQTT 字段 (port 1883 明文) ==='
    echo 'fmt: frame|msgtype|topic|username|passwd|payload_hex'
    echo 'msgtype: 1=CONNECT 3=PUBLISH 8=SUBSCRIBE ...'
    tshark -r "$LAB/pcap/plain-1883.pcap" -Y mqtt -T fields -E separator='|' \
      -e frame.number -e mqtt.msgtype -e mqtt.topic -e mqtt.username -e mqtt.passwd -e mqtt.msg 2>/dev/null
    echo
    echo '=== payload_hex 解码 ==='
    python3 - <<'PY'
hx='68656c6c6f2d706c61696e2d6d717474'
print('68656c6c6f2d706c61696e2d6d717474 ->', bytes.fromhex(hx).decode())
print('username=lab  passwd=lab  (见 CONNECT msgtype=1 行)')
PY
    echo
    echo '=== strings 直接读到的明文 ==='
    strings "$LAB/pcap/plain-1883.pcap" | grep -E 'lab/demo|hello-plain-mqtt' | head -5
    echo
    echo '结论: 账号密码和消息正文在 1883 上全是明文'
  } > /tmp/show-05.txt

  {
    echo '=== QoS 抓包字段 ==='
    echo 'fmt: msgtype|qos|topic|payload_hex'
    tshark -r "$LAB/pcap/qos-1883.pcap" -Y 'mqtt.msgtype==3' -T fields -E separator='|' \
      -e mqtt.msgtype -e mqtt.qos -e mqtt.topic -e mqtt.msg 2>/dev/null
    echo
    echo '说明: 三条 PUBLISH 的 qos 分别是 0/1/2，payload 仍是明文可读'
    echo '结论: QoS 只管投递可靠度，不管保密和防伪造'
  } > /tmp/show-10.txt

  {
    echo '=== 11 明文 1883 (profile 05-tls-compare) ==='
    ss -lntp 2>/dev/null | grep -E '1883|8883' || true
    echo
    echo 'fmt: msgtype|topic|username|payload_hex'
    tshark -r "$LAB/pcap/compare-plain.pcap" -Y mqtt -T fields -E separator='|' \
      -e mqtt.msgtype -e mqtt.topic -e mqtt.username -e mqtt.msg 2>/dev/null | head -20
    echo
    strings "$LAB/pcap/compare-plain.pcap" | grep -E 'this-is-plain|lab/user' | head -5
    echo
    echo '结论: 1883 上 MQTT 主题和正文都能直接解出来'
  } > /tmp/show-11.txt

  {
    echo '=== 12 TLS 8883 ==='
    echo '--- mqtt 过滤 (应为空 = 解不出 MQTT) ---'
    out=$(tshark -r "$LAB/pcap/compare-tls.pcap" -Y mqtt 2>/dev/null | head -5 || true)
    if [[ -z "${out// }" ]]; then
      echo '(empty) 好：密文里看不到 MQTT 字段'
    else
      echo "$out"
    fi
    echo
    echo '--- tls 记录类型 (content_type) ---'
    tshark -r "$LAB/pcap/compare-tls.pcap" -Y tls -T fields -E separator='|' \
      -e frame.number -e tls.record.content_type 2>/dev/null | head -20
    echo
    echo '--- strings 搜 this-is-tls (应找不到明文) ---'
    if strings "$LAB/pcap/compare-tls.pcap" | grep -q 'this-is-tls'; then
      echo '意外: 找到了明文 this-is-tls'
    else
      echo '未找到 this-is-tls 明文 (符合预期)'
    fi
    echo
    echo '结论: 8883 只见 TLS，MQTT 用户名/密码/正文被包在加密层里'
  } > /tmp/show-12.txt

  echo "[+] pcaps ready"
  wc -l /tmp/show-05.txt /tmp/show-10.txt /tmp/show-11.txt /tmp/show-12.txt
}

for i in 0 1 2; do clearp $i; done

prepare_pcaps

# ========== 05 明文抓包 ==========
switch 01-insecure
run0 "echo '=== 05 明文 MQTT 抓包证据 ==='; cat /tmp/show-05.txt"
run1 "echo '命令回顾'; echo '1) tcpdump -i any -w plain-1883.pcap \"tcp port 1883\"'; echo '2) mosquitto_pub -u lab -P lab -t lab/demo -m hello-plain-mqtt'; echo '3) tshark -Y mqtt 看字段'"
run2 "echo '要点'; echo '用户名 lab / 密码 lab 明文'; echo 'payload hello-plain-mqtt 明文'; echo '内网嗅探即可读'"
shot 05-pcap-connect 1.4

# ========== 06 伪造前 ==========
seed
run0 "echo '=== 06 伪造前: 设备主题现状 ==='; mosquitto_sub -h $HOST -p 1883 -t 'home/device1/#' -v -W 2; echo; echo '上面是 seed 的正常状态'"
run1 "echo '主题: home/device1/status 与 cmd'"
run2 "echo '下一步用任意客户端 pub 覆写 retained'"
shot 06-forge-before 2.8

# ========== 07 伪造后 ==========
mosquitto_pub -h "$HOST" -p 1883 -t 'home/device1/status' -r \
  -m '{"online":true,"temp":99.9,"note":"forged-by-attacker"}'
mosquitto_pub -h "$HOST" -p 1883 -t 'home/device1/cmd' -r \
  -m '{"power":"on","by":"nobody-checked-identity"}'
run0 "echo '=== 07 伪造后: 再订 home/device1/# ==='; mosquitto_sub -h $HOST -p 1883 -t 'home/device1/#' -v -W 2; echo; echo '对比 06: temp 变成 99.9, cmd 变成 on, note=forged'"
run1 "echo '攻击命令:'; echo \"mosquitto_pub -t home/device1/status -r -m '{...forged...}'\""
run2 "echo '无 ACL + 匿名/任意账号 => 谁都能改状态'"
shot 07-forge-after 2.8

# ========== 10 QoS ==========
run0 "echo '=== 10 QoS 对照 (抓包看 qos 字段) ==='; cat /tmp/show-10.txt"
run1 "echo '三条 PUBLISH:'; echo 'q0-at-most-once'; echo 'q1-at-least-once'; echo 'q2-exactly-once'"
run2 "echo 'QoS ≠ 安全'; echo '要保密仍靠 TLS'; echo '要鉴权仍靠账号+ACL'"
shot 10-qos 1.4

# ========== 11 明文对照 ==========
switch 05-tls-compare
run0 "echo '=== 11 TLS 对照之明文侧 1883 ==='; cat /tmp/show-11.txt"
run1 "echo '同一账号 lab/lab'; echo '同一主题 lab/user/hello'; echo '端口 1883 无加密'"
run2 "echo '下一张同一操作走 8883'"
shot 11-tls-plain 1.4

# ========== 12 TLS ==========
run0 "echo '=== 12 TLS 对照之加密侧 8883 ==='; cat /tmp/show-12.txt"
run1 "echo '客户端:'; echo 'mosquitto_pub -p 8883 --cafile ca.crt ...'"
run2 "echo '对比 11: 明文没了'; echo '只剩 TLS Application Data'"
shot 12-tls-cipher 1.4

# restore demo state
switch 01-insecure
seed
bash "$LAB/scripts/seed-retained.sh" >/dev/null 2>&1 || true
# undo forge for cleanliness
mosquitto_pub -h "$HOST" -p 1883 -t 'home/device1/status' -r -m '{"online":true,"temp":26.5}' >/dev/null
mosquitto_pub -h "$HOST" -p 1883 -t 'home/device1/cmd' -r -m '{"power":"off"}' >/dev/null

for i in 0 1 2; do clearp $i; done
run0 "echo '关键图补拍完成: 05 06 07 10 11 12'; ls -la $SHOTS/0{5,6,7}*.png $SHOTS/1{0,1,2}*.png 2>/dev/null | awk '{print \$5,\$9}'"
run1 "echo 'DISPLAY=$DISPLAY 虚拟桌面'"
run2 "echo '未占用 GNOME 前台'"
sleep 0.8

echo
echo "[+] key shots done"
ls -la "$SHOTS"/05-pcap-connect.png "$SHOTS"/06-forge-before.png "$SHOTS"/07-forge-after.png \
  "$SHOTS"/10-qos.png "$SHOTS"/11-tls-plain.png "$SHOTS"/12-tls-cipher.png
