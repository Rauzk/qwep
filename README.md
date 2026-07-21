# Mosquitto MQTT 安全靶场（入门实验）

这是个**简陋靶场**：配置故意写得不安全，用来做入门对照，不是成品安全方案，也别当生产环境用。

本仓库是 **授权本地实验** 用的 Mosquitto MQTT 靶场与笔记：匿名访问、弱口令、明文抓包、ACL 过宽、消息伪造、QoS、TLS 对照、轻量 DoS 观察。

> 只在自己搭的环境里做，不要拿去扫别人的 broker。

## 文档

- 完整实验笔记（图文）：**[note.md](./note.md)**
- 截图目录：`shots/`
- 靶场配置与脚本：`lab/`

## 仓库

- GitHub：https://github.com/Rauzk/qwep

## 快速开始

```sh
sudo bash lab/scripts/install-lab.sh 01-insecure
bash lab/scripts/seed-retained.sh
bash lab/scripts/lab-status.sh
```

切换实验 profile：

```sh
sudo bash lab/scripts/switch-profile.sh 01-insecure
sudo bash lab/scripts/switch-profile.sh 02-auth-weak
sudo bash lab/scripts/switch-profile.sh 03-acl-wide
sudo bash lab/scripts/switch-profile.sh 04-acl-strict
sudo bash lab/scripts/switch-profile.sh 05-tls-compare
```

## 目录说明

```text
note.md           实验正文（大白话步骤 + 截图）
shots/            01–13 步骤截图
lab/profiles/     五套 mosquitto 配置
lab/acl/          宽/严 ACL
lab/scripts/      安装、切换、seed、关键图补拍
lab/certs/        实验用自签证书（仅 lab）
lab/passwd/       弱口令清单（仅 lab）
```

## 声明

简陋靶场，配置故意存在不安全项，仅供学习对照。自签私钥、弱口令均为靶场演示数据，**不要用于生产**。
