# 截图清单（与 note.md 图注一一对应）

| 文件 | 对应章节 | 图上应能直接读出 |
|---|---|---|
| 01-env-ports.png | 端口监听 | profile=01-insecure，1883/9001 |
| 02-anon-hash.png | 匿名 `#` 扫主题 | token / password 等 retained |
| 03-auth-reject.png | 关匿名被拒 | not authorised |
| 04-auth-lab.png | lab/lab 登录成功 | 能订到主题 |
| 05-pcap-connect.png | 明文抓包 | username/passwd=lab，payload→hello-plain-mqtt |
| 06-forge-before.png | 伪造前 | temp≈26.5，power=off |
| 07-forge-after.png | 伪造后 | temp=99.9，forged-by-attacker |
| 08-acl-wide.png | 宽 ACL | attacker 仍能读密钥 |
| 09-acl-strict.png | 严 ACL | device1 读不到 factory secret |
| 10-qos.png | QoS | 三条 qos=0/1/2，payload 仍明文 |
| 11-tls-plain.png | 1883 对照 | this-is-plain 可解 |
| 12-tls-cipher.png | 8883 对照 | mqtt 空；搜不到 this-is-tls |
| 13-dos.png | 轻量 DoS | 连接数/日志异常 |

关键图补拍（Xvfb `:99`，不占前台）：

```sh
export DISPLAY=:99
bash ../lab/scripts/capture-key-shots.sh
```

本目录截图属于简陋靶场实验记录。

同步批次: git commit 更新
