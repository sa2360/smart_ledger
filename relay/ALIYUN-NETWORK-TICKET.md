# 阿里云工单：广州 ECS 无法连接 Let's Encrypt ACME 接口

用户授权后，已于 2026-09-20 00:26（北京时间）提交给阿里云，工单 ID `00085S9EWE`。
状态：待用户反馈。工程师已回复；2026-09-21 复测已恢复连接，尚未向工单提交本次结果。
链接：https://smartservice.console.aliyun.com/service/chat?entrance=100&id=00085S9EWE&product=ecs
以下为提交内容的本地记录，无密码、私钥或 API 密钥。

## 2026-09-21 跟进

- 工程师于 09-20 00:31 表示 API 托管于 Cloudflare，认为跨境链路可能导致不可达，
  建议 `traceroute -T -p 443 172.65.32.248`；01:00 建议客户端代理或替代 CA。
- 09-21 通过云助手安装 Ubuntu 仓库的 traceroute 并执行 TCP 路由测试。
  末端第 12 跳 `219.158.33.194`（177.514 ms），第 13 跳 `141.101.72.123`（176.826 ms），
  第 14 跳到达 `172.65.32.248`（172.396 ms）。中间星号不能单独证明业务丢包。
- 同次 curl：`ACME status=200 remote=172.65.32.248`；旧中转健康检查正常。
- 未调整出站规则、配置代理或购买域名，随后成功签发 IP 证书并启用 HTTPS。
- 本地电脑以正常证书校验访问 HTTPS 健康检查成功，AI 探测返回 `OK`。
- 自动续期任务已配置；带 `--no-random-sleep-on-renew` 的演练输出全部模拟续期成功。
  同次命令中后续重复演练超时，未更改已生效的生产证书。
- 这是当前恢复的证据，不保证后续跨境路径持续稳定。

以下保留原工单提交时的故障记录。

## 问题

2026-09-19，广州 ECS 访问 `https://acme-v02.api.letsencrypt.org/directory`
持续 TCP 连接超时，导致无法申请 HTTPS 证书。请协助检查实例出站路径、
云侧访问控制及到目标网络的路由，说明故障位置和可持续修复方法。
当前业务中转仍正常运行，请勿重装、重启或修改公网 IP。

## 实例

- 地域：cn-guangzhou
- 实例 ID：i-7xvc1316vabqj2awctn5
- 公网 IP：8.163.98.62
- 系统：Ubuntu 22.04.5 LTS
- 安全组：sg-7xv7h5qzkbvavzvxd72p，普通安全组，无自定义出方向规则

## 已完成排查

- DNS A 记录：172.65.32.248；本地电脑解析结果一致。
- 路由：172.65.32.248 via 172.16.31.253 dev eth0 src 172.16.28.239。
- 实例 `iptables -S OUTPUT`：`-P OUTPUT ACCEPT`，无额外规则。
- UFW 未启用。
- 使用 `curl --noproxy '*' -4` 排除代理影响后，ACME 地址仍连接超时，HTTP 状态 000。
- 同一实例访问 `https://letsencrypt.org/` 返回 HTTP 200。
- IPv6 连接也失败，当前没有可用的 IPv6 外联。
- 同时段本地电脑访问相同 ACME 地址成功，返回目录 JSON。
- 旧服务 `http://127.0.0.1:8000/health` 返回正常，本地电脑访问公网 8000 也正常。
- 入方向 TCP 80 和 443 已放行，HTTP ACME 验证站点已配置。
- Certbot 5.8.0 签发失败于连接 ACME 目录阶段，尚未发起 HTTP 验证。

## 复现命令

```sh
curl --noproxy '*' -4 -sS --connect-timeout 8 --max-time 12 -o /dev/null -w 'ACME status=%{http_code} remote=%{remote_ip}\n' https://acme-v02.api.letsencrypt.org/directory
curl --noproxy '*' -4 -sS --connect-timeout 8 --max-time 12 -o /dev/null -w 'LE site status=%{http_code}\n' https://letsencrypt.org/
```

云助手排查执行 ID：`t-gz06xiz2k4pfj7k`。
