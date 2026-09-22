# 一语记中转服务

纯 Node.js，无第三方运行依赖。推荐 Node.js 20 或更新版本。

现有阿里云服务器 `8.163.98.62` 的迁移顺序见 [ALIYUN-MIGRATION.md](ALIYUN-MIGRATION.md)，支持不购买域名、使用 IP 地址证书。

## 接口

- `GET /`、`GET /health`：健康状态。
- `POST /v1/chat/completions`（也接受 `/chat/completions`）：OpenAI 兼容请求原样转发至 `AGNES_UPSTREAM`，服务端注入 `AGNES_KEY`。
- `POST /asr`：接收 `speech`（PCM base64）、`len`、`cuid`，服务端使用百度密钥换取 token 后识别。
- `GET /debug-net`：仅 `ENABLE_NETWORK_DIAGNOSTICS=true` 时开启，默认关闭。

请求正文上限：对话 4 MiB、语音 14 MiB。百度 token 内存缓存 29 天。

## 私有配置

参考 `.env.example`。服务器提供 `AGNES_KEY`、`BAIDU_API_KEY`、`BAIDU_SECRET_KEY`，不要放进脚本、仓库或 APK。
服务使用 `process.env`，不会自动加载 `.env` 文件。Linux 部署由 systemd `EnvironmentFile` 注入，DomCloud 使用平台私有环境配置。
App 构建参数为 `LLM_RELAY_URL=https://域名/v1`、`ASR_RELAY_URL=https://域名` 和 `LLM_MODEL`。

## Linux / 阿里云

1. 安装 Node.js，将 `server.js` 和 `deploy-aliyun.sh` 上传到同一目录。
2. 在服务器创建 `/etc/yiyuji/relay.env`，填写实际密钥，权限设为 `600`，不要使用仓库曾经出现过的旧值。
3. 执行 `sudo bash deploy-aliyun.sh`。脚本从同目录复制唯一的 `server.js`，通过专用低权限用户运行。
4. 服务监听 `127.0.0.1:8000`；通过有有效证书的 HTTPS 反向代理暴露公网，不开放后端端口。
5. 验证 `https://你的域名/health`。更新源码后重新运行脚本。

代理配置示例（放入已有 HTTPS server 块中）：

```nginx
location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_read_timeout 130s;
    client_max_body_size 14m;
}
```

只有反向代理覆盖了转发头且后端不可被公网直接访问时，才设置 `TRUST_PROXY=true`，否则默认使用 TCP 客户端地址。

## DomCloud

将 `server.js` 上传到 `public_html/relay.js`，设置私有环境变量，使用 `deploy-domcloud.yml`。
部署文件不含密钥或重复嵌入的服务源码。端口遵循平台注入的 `PORT`，监听地址可通过 `HOST` 配置。
如平台要求外部容器访问，设置相应监听地址，并保证代理与访问控制配置一致。

## 限流

| 环境变量 | 默认值 |
|---|---:|
| `CHAT_DAILY_LIMIT_PER_IP` | 200 |
| `CHAT_DAILY_LIMIT_GLOBAL` | 2000 |
| `ASR_DAILY_LIMIT_PER_IP` | 100 |
| `ASR_DAILY_LIMIT_GLOBAL` | 1000 |

设置为 0 表示该维度不限。计数按 UTC 日期重置，进程重启清零；请求失败也计入次数。
当前中转不含用户账户鉴权，公开部署应在网关控制访问；默认限流不能替代账户授权。

## 验证与旧凭据

```sh
node --check server.js
node --test server.test.js
```

测试使用本机临时端口，无上游请求。旧版本部署文件包含过明文密钥，移出源码不代表已撤销：需要在服务商控制台轮换，并将新值只保存在服务端。
