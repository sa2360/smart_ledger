#!/usr/bin/env bash
set -euo pipefail
test "${EUID}" -eq 0 || { echo '请使用 sudo 运行'; exit 1; }
# 在服务器上将 server.js 放在本脚本旁，然后 sudo bash deploy-aliyun.sh。
# 凭据先保存在 /etc/yiyuji/relay.env（参考 .env.example），不写入仓库。
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null || { echo '请先安装 Node.js 20 或更新版本'; exit 1; }
node --check "$SCRIPT_DIR/server.js"
test -s /etc/yiyuji/relay.env || { echo '请先配置 /etc/yiyuji/relay.env'; exit 1; }
BACKUP="$(mktemp -d /root/yiyuji-before-deploy-XXXXXXXX)"
chmod 700 "$BACKUP"
for file in /opt/yiyuji/relay.js /etc/systemd/system/yiyuji-relay.service; do
  if test -e "$file"; then cp -p "$file" "$BACKUP/$(basename "$file")"; fi
done
WAS_ACTIVE=false
WAS_ENABLED=false
systemctl is-active --quiet yiyuji-relay && WAS_ACTIVE=true
systemctl is-enabled --quiet yiyuji-relay && WAS_ENABLED=true
rollback() {
  local status=$?
  trap - ERR
  echo '部署失败，正在恢复先前服务。'
  systemctl stop yiyuji-relay || true
  if test -f "$BACKUP/relay.js"; then cp -p "$BACKUP/relay.js" /opt/yiyuji/relay.js; fi
  if test -f "$BACKUP/yiyuji-relay.service"; then
    cp -p "$BACKUP/yiyuji-relay.service" /etc/systemd/system/yiyuji-relay.service
  else
    rm -f -- /etc/systemd/system/yiyuji-relay.service
  fi
  systemctl daemon-reload || true
  if "$WAS_ENABLED"; then systemctl enable yiyuji-relay || true; else systemctl disable yiyuji-relay || true; fi
  if "$WAS_ACTIVE"; then systemctl start yiyuji-relay || true; fi
  echo "先前文件备份：$BACKUP（仅 root 可读）"
  exit "$status"
}
trap rollback ERR
id yiyuji >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin yiyuji
install -d -m 755 /opt/yiyuji
install -m 644 "$SCRIPT_DIR/server.js" /opt/yiyuji/relay.js.next
mv -f /opt/yiyuji/relay.js.next /opt/yiyuji/relay.js
chmod 600 /etc/yiyuji/relay.env
node --check /opt/yiyuji/relay.js
cat > /etc/systemd/system/yiyuji-relay.service <<'UNIT'
[Unit]
Description=Yiyuji AI Relay
After=network.target
[Service]
ExecStart=/usr/bin/env HOST=127.0.0.1 PORT=8000 node /opt/yiyuji/relay.js
EnvironmentFile=/etc/yiyuji/relay.env
Environment=HOST=127.0.0.1
Environment=PORT=8000
Restart=on-failure
RestartSec=3
User=yiyuji
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable yiyuji-relay
systemctl restart yiyuji-relay
curl --fail --retry 10 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8000/health
trap - ERR
echo "先前文件备份：$BACKUP（仅 root 可读）"
printf '\n请通过 HTTPS 反向代理对外提供服务。\n'
