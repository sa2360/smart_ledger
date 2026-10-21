#!/usr/bin/env bash
# Ubuntu 22.04/24.04: sudo bash setup-https-ip.sh 8.163.98.62 [联系邮箱]
# 先在安全组放行 TCP 80、443。本脚本不关闭或重启现有 8000 中转。
set -euo pipefail
test "${EUID}" -eq 0 || { echo '请使用 sudo 运行'; exit 1; }
PUBLIC_IP="${1:?用法：setup-https-ip.sh 公网IPv4 [联系邮箱]}"
python3 -c 'import ipaddress,sys; a=ipaddress.IPv4Address(sys.argv[1]); assert a.is_global' "$PUBLIC_IP"
CONTACT_EMAIL="${2:-}"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx snapd
systemctl enable --now snapd.socket
if ! snap list certbot >/dev/null 2>&1; then
  snap install certbot --classic
fi
CERTBOT=/snap/bin/certbot
"$CERTBOT" --version
CERTBOT_HELP="$("$CERTBOT" --help all)"
grep -q -- '--ip-address' <<< "$CERTBOT_HELP" || {
  echo 'Certbot 需支持 IP 地址证书（webroot 至少 5.4）；请先更新 Certbot'; exit 1;
}
install -d -m 755 /var/www/yiyuji-acme
CONFIG=/etc/nginx/conf.d/yiyuji-ip.conf
BACKUP="${CONFIG}.before-$(date +%Y%m%d%H%M%S)"
if test -e "$CONFIG"; then cp -p "$CONFIG" "$BACKUP"; fi

# 只创建本应用的配置，不删除默认站点或其他站点。
# 若证书已存在，保留现有 HTTPS，避免更新时暂时撤掉 443。
if ! test -s "/etc/letsencrypt/live/${PUBLIC_IP}/fullchain.pem"; then
  cat > "$CONFIG" <<NGINX
server {
    listen 80;
    server_name ${PUBLIC_IP};
    location /.well-known/acme-challenge/ { root /var/www/yiyuji-acme; }
    location / { return 404; }
}
NGINX
  if ! nginx -t; then
    if test -e "$BACKUP"; then cp -p "$BACKUP" "$CONFIG"; else rm -f -- "$CONFIG"; fi
    exit 1
  fi
  systemctl enable --now nginx
  systemctl reload nginx
fi

CONTACT_ARGS=(--register-unsafely-without-email)
if test -n "$CONTACT_EMAIL"; then CONTACT_ARGS=(--email "$CONTACT_EMAIL"); fi
"$CERTBOT" certonly --non-interactive --agree-tos "${CONTACT_ARGS[@]}" \
  --preferred-profile shortlived --webroot --webroot-path /var/www/yiyuji-acme \
  --ip-address "$PUBLIC_IP" --cert-name "$PUBLIC_IP" --keep-until-expiring

cat > "$CONFIG" <<NGINX
server {
    listen 80;
    server_name ${PUBLIC_IP};
    location /.well-known/acme-challenge/ { root /var/www/yiyuji-acme; }
    location / { return 301 https://${PUBLIC_IP}\$request_uri; }
}
server {
    listen 443 ssl;
    server_name ${PUBLIC_IP};
    ssl_certificate /etc/letsencrypt/live/${PUBLIC_IP}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PUBLIC_IP}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 14m;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_read_timeout 130s;
    }
}
NGINX
if ! nginx -t; then
  if test -e "$BACKUP"; then cp -p "$BACKUP" "$CONFIG"; fi
  exit 1
fi
systemctl enable --now nginx
systemctl reload nginx

# IP 证书只有约 6 天有效期，必须自动续期并 reload 才能生效。
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/yiyuji-nginx.sh <<'HOOK'
#!/bin/sh
nginx -t && systemctl reload nginx
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/yiyuji-nginx.sh
cat > /etc/systemd/system/yiyuji-cert-renew.service <<UNIT
[Unit]
Description=Renew Yiyuji HTTPS certificate
[Service]
Type=oneshot
ExecStart=/snap/bin/certbot renew --cert-name ${PUBLIC_IP} --quiet --no-random-sleep-on-renew
UNIT
cat > /etc/systemd/system/yiyuji-cert-renew.timer <<'UNIT'
[Unit]
Description=Check Yiyuji certificate renewal every six hours
[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
RandomizedDelaySec=15min
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
# 先演练再启动本项目的 timer，避免 OnBootSec 已过时立即触发并争用 Certbot 锁。
# 演练失败也保留自动续期任务，但返回失败让部署者处理原因。
RENEW_TEST_STATUS=0
"$CERTBOT" renew --cert-name "$PUBLIC_IP" --dry-run --no-random-sleep-on-renew || RENEW_TEST_STATUS=$?
systemctl enable --now yiyuji-cert-renew.timer
test "$RENEW_TEST_STATUS" -eq 0 || exit "$RENEW_TEST_STATUS"
curl --fail --max-time 15 "https://${PUBLIC_IP}/health"
printf '\nHTTPS 已验证。安装新版 APK 并确认可用后，再关闭公网 8000 端口。\n'
