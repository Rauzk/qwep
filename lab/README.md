# MQTT Lab（本地授权靶场）

简陋靶场，配置故意不安全，仅供入门实验对照，勿用于生产。

## mqtt-pwn

```sh
# 依赖：/tmp/mqtt-pwn + docker compose db(5431)
bash scripts/demo-mqtt-pwn.sh wordlists/usernames.txt wordlists/passwords.txt discovery
bash scripts/demo-mqtt-pwn.sh wordlists/usernames.txt wordlists/passwords.txt brute
```

交互壳：`bash /tmp/mqtt-pwn/run_mqtt_pwn.sh`  
常用：`connect` / `discovery` / `topics` / `messages` / `bruteforce` / `system_info`

## 安装

```sh
sudo bash scripts/install-lab.sh 01-insecure
bash scripts/seed-retained.sh
bash scripts/lab-status.sh
```

## 切换 profile

```sh
sudo bash scripts/switch-profile.sh 01-insecure
sudo bash scripts/switch-profile.sh 02-auth-weak
sudo bash scripts/switch-profile.sh 03-acl-wide
sudo bash scripts/switch-profile.sh 04-acl-strict
sudo bash scripts/switch-profile.sh 05-tls-compare
```

| profile | 含义 |
|---|---|
| 01-insecure | 匿名 + 明文 + 无 ACL |
| 02-auth-weak | 关匿名 + 弱口令 |
| 03-acl-wide | 登录 + ACL 全是 `#` |
| 04-acl-strict | 登录 + 最小 ACL |
| 05-tls-compare | 1883 明文 + 8883 TLS |

## 弱口令

见 `passwd/accounts.txt`（lab/lab、admin/admin…）。

## TLS 客户端

```sh
mosquitto_sub -h 192.168.2.127 -p 8883 -u lab -P lab \
  --cafile /usr/local/share/mqtt-lab/ca.crt -t 'lab/#' -v
```

系统配置落点：`/etc/mosquitto/lab/`，当前 profile 名在 `ACTIVE_PROFILE`。
