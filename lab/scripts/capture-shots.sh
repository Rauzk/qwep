#!/usr/bin/env bash
# 在独立 Xvfb :99 虚拟桌面截图，不占用 GNOME 前台
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="$ROOT/lab"
SHOTS="$ROOT/shots"
HOST="${MQTT_HOST:-192.168.2.127}"
export DISPLAY="${DISPLAY:-:99}"

mkdir -p "$SHOTS" "$LAB/pcap"

need_display() {
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1
}

shot() {
  local name="$1"
  sleep "${2:-0.8}"
  rm -f "$SHOTS/${name}.png" "$SHOTS/${name}_"*.png 2>/dev/null || true
  scrot -D "$DISPLAY" "$SHOTS/${name}.png"
  # 若 scrot 因重名写成 _000，拨正
  if [[ ! -f "$SHOTS/${name}.png" ]]; then
    local alt
    alt=$(ls -1t "$SHOTS/${name}"_*.png 2>/dev/null | head -1 || true)
    [[ -n "$alt" ]] && mv -f "$alt" "$SHOTS/${name}.png"
  fi
  echo "[shot] ${name}.png ($(stat -c%s "$SHOTS/${name}.png") bytes)"
}

# panes: 0 top, 1 bottom-left, 2 bottom-right (created without -p for tmux 3.4)
WIN="mqtt-lab:0"
clearp() { tmux send-keys -t "$WIN.$1" C-c 2>/dev/null || true; sleep 0.15; tmux send-keys -t "$WIN.$1" "clear" Enter; sleep 0.15; }
run0() { clearp 0; tmux send-keys -t "$WIN.0" "$*" Enter; }
run1() { clearp 1; tmux send-keys -t "$WIN.1" "$*" Enter; }
run2() { clearp 2; tmux send-keys -t "$WIN.2" "$*" Enter; }

switch() {
  sudo bash "$LAB/scripts/switch-profile.sh" "$1" >/tmp/mqtt-switch.log 2>&1
  sleep 0.6
}

seed() {
  local u="${1:-}" p="${2:-}"
  if [[ -n "$u" ]]; then
    MQTT_USER="$u" MQTT_PASS="$p" bash "$LAB/scripts/seed-retained.sh" >/tmp/mqtt-seed.log 2>&1
  else
    bash "$LAB/scripts/seed-retained.sh" >/tmp/mqtt-seed.log 2>&1
  fi
}

if ! need_display; then
  echo "[!] DISPLAY $DISPLAY 不可用。先启动 Xvfb/openbox/xterm。"
  exit 1
fi

tmux has-session -t mqtt-lab 2>/dev/null || {
  echo "[!] tmux session mqtt-lab 不存在"
  exit 1
}

# 停掉各 pane 可能卡住的前台命令
for i in 0 1 2; do clearp $i; done

echo "[*] capture on DISPLAY=$DISPLAY host=$HOST"

# ---------- 01 env ----------
switch 01-insecure
seed
run0 "echo '=== 01 环境端口 ==='; echo profile=\$(cat /etc/mosquitto/lab/ACTIVE_PROFILE); echo; ss -lntp | grep -E '1883|8883|9001' || true; echo; ip -br a | grep -E 'wlx|192.168.2' || true; echo; echo broker: $HOST"
run1 "echo '客户端工具'; mosquitto_sub --help 2>&1 | head -3; which mosquitto_pub mosquitto_sub tcpdump tshark"
run2 "echo 'lab 目录'; ls -la $LAB/profiles; echo; ls $LAB/scripts | head"
shot 01-env-ports 1.2

# ---------- 02 anon hash ----------
run0 "echo '=== 02 匿名订阅 # ==='; mosquitto_sub -h $HOST -p 1883 -t '#' -v -W 3; echo; echo exit=\$?"
run1 "echo '订 \$SYS'; mosquitto_sub -h $HOST -p 1883 -t '\$SYS/broker/version' -v -W 2 || true"
run2 "echo '要点: allow_anonymous true + 无 ACL => # 一把梭'"
shot 02-anon-hash 3.5

# ---------- 03 auth reject ----------
switch 02-auth-weak
run0 "echo '=== 03 关匿名后匿名连接 ==='; mosquitto_sub -h $HOST -p 1883 -t '#' -v -W 2; echo exit=\$?"
run1 "echo profile=\$(cat /etc/mosquitto/lab/ACTIVE_PROFILE)"
run2 "echo 期望: not authorised"
shot 03-auth-reject 2.5

# ---------- 04 auth lab ----------
run0 "echo '=== 04 弱口令 lab/lab ==='; mosquitto_sub -h $HOST -p 1883 -u lab -P lab -t '#' -v -W 3; echo"
run1 "echo '错密码'; mosquitto_sub -h $HOST -p 1883 -u lab -P wrong -t '#' -W 2; echo exit=\$?"
run2 "echo 认证开了, 但口令太弱仍危险"
shot 04-auth-lab 3.5

# ---------- 05 pcap ----------
switch 01-insecure
seed
# start capture in pane1
clearp 1
tmux send-keys -t "$WIN.1" "echo '=== 05 明文抓包 ==='; sudo timeout 8 tcpdump -i any -n -s 0 -w $LAB/pcap/plain-1883.pcap 'tcp port 1883' 2>&1 | tail -5" Enter
sleep 1.2
run0 "echo '发一条带账号的消息'; mosquitto_pub -h $HOST -p 1883 -u lab -P lab -t 'lab/demo' -m 'hello-plain-mqtt'; sleep 1; echo done_pub"
sleep 6
run0 "echo '=== tshark 看 MQTT 字段 ==='; tshark -r $LAB/pcap/plain-1883.pcap -Y mqtt -T fields -e frame.number -e mqtt.msgtype -e mqtt.topic -e mqtt.username -e mqtt.passwd -e mqtt.msg 2>/dev/null | head -30"
run2 "echo CONNECT 用户名密码 / PUBLISH payload 都是明文"
shot 05-pcap-connect 2.5

# ---------- 06 forge before ----------
switch 01-insecure
seed
clearp 1
tmux send-keys -t "$WIN.1" "echo '=== 订阅设备主题 ==='; mosquitto_sub -h $HOST -p 1883 -t 'home/device1/#' -v" Enter
sleep 1.5
run0 "echo '=== 06 伪造前 ==='; mosquitto_sub -h $HOST -p 1883 -t 'home/device1/#' -v -W 2"
run2 "echo 当前 retained 是 seed 的正常状态"
shot 06-forge-before 2.5

# ---------- 07 forge after ----------
# kill hanging sub in pane1
clearp 1
run0 "echo '=== 07 伪造消息 ==='; mosquitto_pub -h $HOST -p 1883 -t 'home/device1/status' -r -m '{\"online\":true,\"temp\":99.9,\"note\":\"forged-by-attacker\"}'; mosquitto_pub -h $HOST -p 1883 -t 'home/device1/cmd' -r -m '{\"power\":\"on\",\"by\":\"nobody-checked-identity\"}'; echo forged; echo; mosquitto_sub -h $HOST -p 1883 -t 'home/device1/#' -v -W 2"
run1 "echo 订阅端立刻看到假状态/假指令"
run2 "echo retained 被污染, 后来客户端也会上当"
shot 07-forge-after 3

# ---------- 08 acl wide ----------
switch 03-acl-wide
seed lab lab
run0 "echo '=== 08 宽 ACL: attacker 订 # ==='; mosquitto_sub -h $HOST -p 1883 -u attacker -P attacker -t '#' -v -W 3"
run1 "echo profile=\$(cat /etc/mosquitto/lab/ACTIVE_PROFILE); echo 'wide.acl: topic readwrite #'"
run2 "echo 有登录也没用, # 全开等于没隔离"
shot 08-acl-wide 3.5

# ---------- 09 acl strict ----------
switch 04-acl-strict
seed admin admin
run0 "echo '=== 09 严 ACL ==='; echo '[device1 写自己]'; mosquitto_pub -h $HOST -p 1883 -u device1 -P device1 -t 'home/device1/status' -m '{\"online\":true}' -r && echo OK; echo; echo '[device1 读工厂密钥 - 应无数据]'; mosquitto_sub -h $HOST -p 1883 -u device1 -P device1 -t 'factory/secret/token' -v -W 2; echo; echo '[attacker 只能 lab/public]'; mosquitto_sub -h $HOST -p 1883 -u attacker -P attacker -t 'lab/public' -v -W 2; echo; echo '[attacker 订 # 扩不到密钥]'; mosquitto_sub -h $HOST -p 1883 -u attacker -P attacker -t '#' -v -W 2"
run1 "echo strict.acl 按角色砍权限"
run2 "echo device1 收不到 factory/secret/token"
shot 09-acl-strict 5

# ---------- 10 qos ----------
switch 01-insecure
run0 "echo '=== 10 QoS 对照 ==='; for q in 0 1 2; do mosquitto_pub -h $HOST -p 1883 -t 'lab/qos' -q \$q -m \"q\${q}-payload\"; done; echo published_q0_q1_q2; echo; echo '说明: QoS 只保证投递次数, 不加密也不防伪造'"
run1 "mosquitto_sub -h $HOST -p 1883 -t 'lab/qos' -q 1 -v -W 2 || true"
run2 "echo QoS0 最多一次 / QoS1 至少一次 / QoS2 正好一次"
shot 10-qos 2.5

# ---------- 11 tls plain side ----------
switch 05-tls-compare
# ensure lab can write under strict - use lab topic lab/user
run0 "echo '=== 11 TLS对照: 明文 1883 ==='; ss -lntp | grep -E '1883|8883'; echo; sudo timeout 6 tcpdump -i any -n -s 0 -w $LAB/pcap/compare-plain.pcap 'tcp port 1883' >/tmp/td1.log 2>&1 & sleep 0.8; mosquitto_pub -h $HOST -p 1883 -u lab -P lab -t 'lab/user/hello' -m 'this-is-plain'; sleep 5; echo; tshark -r $LAB/pcap/compare-plain.pcap -Y mqtt -T fields -e mqtt.msgtype -e mqtt.topic -e mqtt.username -e mqtt.msg 2>/dev/null | head -20"
run1 "echo 明文侧仍可解析 MQTT"
run2 "echo profile=05-tls-compare"
shot 11-tls-plain 8

# ---------- 12 tls cipher ----------
run0 "echo '=== 12 TLS对照: 8883 ==='; sudo timeout 6 tcpdump -i any -n -s 0 -w $LAB/pcap/compare-tls.pcap 'tcp port 8883' >/tmp/td2.log 2>&1 & sleep 0.8; mosquitto_pub -h $HOST -p 8883 -u lab -P lab --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/user/hello' -m 'this-is-tls'; mosquitto_sub -h $HOST -p 8883 -u lab -P lab --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/user/hello' -v -W 2; sleep 4; echo; echo '--- mqtt 过滤(应为空) ---'; tshark -r $LAB/pcap/compare-tls.pcap -Y mqtt 2>/dev/null | head -5; echo '(empty means good)'; echo '--- tls 记录 ---'; tshark -r $LAB/pcap/compare-tls.pcap -Y tls -T fields -e frame.number -e tls.record.content_type 2>/dev/null | head -15"
run1 "echo 8883 只能看到 TLS Application Data"
run2 "echo MQTT 明文字段解不出来"
shot 12-tls-cipher 9

# ---------- 13 dos light ----------
switch 01-insecure
run0 "echo '=== 13 轻量 DoS 观察 ==='; echo before_conns=\$(ss -tpn 2>/dev/null | grep -c 1883 || true); for i in \$(seq 1 80); do mosquitto_sub -h $HOST -p 1883 -t lab/dos/\$i -W 1 >/dev/null 2>&1 & done; sleep 2; echo after_conns=\$(ss -tpn 2>/dev/null | grep -c 1883 || true); echo; echo '日志摘录:'; sudo tail -n 15 /var/log/mosquitto/mosquitto.log 2>/dev/null | tail -15; wait 2>/dev/null || true"
run1 "echo 只在自己靶场短时间做"
run2 "echo 缓解: max_connections / 限流 / 关匿名"
shot 13-dos 5

# restore default
switch 01-insecure
seed
for i in 0 1 2; do clearp $i; done
run0 "echo '截图完成, 默认已恢复 01-insecure'; ls -la $SHOTS/*.png | sed 's|.*/||'"
run1 "echo shots -> $SHOTS"
run2 "echo DISPLAY=$DISPLAY 虚拟桌面, 未占 GNOME 前台"
shot _done-index 1.5

echo
echo "[+] all shots:"
ls -la "$SHOTS"/*.png
