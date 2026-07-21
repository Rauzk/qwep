#!/usr/bin/env bash
# 生成实验用自签 CA + 服务器证书（CN/SAN 覆盖 lab IP 和本机名）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="${1:-$ROOT/certs}"
DAYS="${DAYS:-3650}"
IP_DEFAULT="192.168.2.127"

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# 已有就跳过，除非 FORCE=1
if [[ -f server.crt && -f server.key && -f ca.crt && "${FORCE:-0}" != "1" ]]; then
  echo "[*] certs already exist in $CERT_DIR (FORCE=1 to regenerate)"
  ls -la
  exit 0
fi

echo "[*] generating CA + server cert into $CERT_DIR"

openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$DAYS" \
  -subj "/O=MQTT-Lab/CN=MQTT-Lab-CA" -out ca.crt

openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -subj "/O=MQTT-Lab/CN=${IP_DEFAULT}" -out server.csr

cat > server.ext <<EOF
subjectAltName = DNS:localhost,DNS:mqtt-lab,IP:127.0.0.1,IP:${IP_DEFAULT}
extendedKeyUsage = serverAuth
keyUsage = digitalSignature, keyEncipherment
EOF

openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days "$DAYS" -sha256 -extfile server.ext 2>/dev/null

chmod 640 server.key ca.key 2>/dev/null || true
rm -f server.csr server.ext

echo "[+] done"
openssl x509 -in server.crt -noout -subject -dates -ext subjectAltName 2>/dev/null || true
ls -la
