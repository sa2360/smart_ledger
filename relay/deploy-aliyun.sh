#!/usr/bin/env bash
set -euo pipefail
# 在服务器上将 server.js 放在本脚本旁，然后 sudo bash deploy-aliyun.sh。
# 凭据先保存在 /etc/yiyuji/relay.env（参考 .env.example），不写入仓库。
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null || { echo '请先安装 Node.js 20 或更新版本'; exit 1; }
test -s /etc/yiyuji/relay.env || { echo '请先配置 /etc/yiyuji/relay.env'; exit 1; }
id yiyuji >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin yiyuji
install -d -m 755 /opt/yiyuji
install -m 644 "$SCRIPT_DIR/server.js" /opt/yiyuji/relay.js
chmod 600 /etc/yiyuji/relay.env
node --check /opt/yiyuji/relay.js
cat > /etc/systemd/system/yiyuji-relay.service <<'UNIT'
[Unit]
Description=Yiyuji AI Relay
After=network.target
[Service]
ExecStart=/usr/bin/env node /opt/yiyuji/relay.js
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
printf '\n请通过 HTTPS 反向代理对外提供服务。\n'
