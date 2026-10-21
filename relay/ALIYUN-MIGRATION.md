# 当前服务器升级：8.163.98.62

2026-10-02 本地在线复测：HTTPS `/health` 返回 200；`agnes-2.5-flash` 回复 `OK`；
将本机合成的 16kHz/16bit/单声道中文 PCM 发送至 `/asr`，返回 HTTP 200、`err_no=0`，
识别结果为「午饭30元，奶茶15元。」。证明当前 AI 和百度语音中转均可用，手机录音流程仍需真机验收。
本轮没有修改服务器部署。生产 APK 参数现已固定在 `config/production.json` 和 `tools/build_release.ps1`。

本次检查时 `http://8.163.98.62:8000/health` 返回正常，说明旧版中转正在运行。
健康检查不代表上游 AI/语音密钥有效。

2026-09-19 已通过阿里云云助手确认 Ubuntu 22.04.5、Node.js 20.20.2，
新增安全组 TCP 80/443 入站规则（保留原 8000），安装 Nginx 和 Certbot 5.8.0。
旧中转程序及 systemd unit 私密备份位于服务器 `/root/yiyuji-before-upgrade-W0DW3PBl`。
证书申请失败：服务器连接 `acme-v02.api.letsencrypt.org:443` 超时，IPv6 无可用连接。
已确认本机 OUTPUT 策略为 ACCEPT，普通安全组无自定义出方向规则（默认允许出站），
服务器访问 `https://letsencrypt.org/` 返回 200，旧中转健康检查正常。
目前证据指向到签发接口的特定网络路径故障，具体阻断位置尚未确定。
以上为 2026-09-19 的故障记录。2026-09-21 复测时，TCP 路由已到达目标，
ACME 目录返回 HTTP 200；未修改出站规则、使用代理或更换域名。
已成功签发 IP 证书（本次签发显示到期日 2026-09-28），启用 Nginx HTTPS。
从本地电脑验证 `https://8.163.98.62/health` 成功，未跳过证书校验；
经 HTTPS 调用 `agnes-2.5-flash` 返回 `OK`。语音识别仍待手机端验证。
已创建每六小时续期 timer 和成功续期后的 Nginx reload hook。
首次续期演练遇到 Certbot 锁占用；随后带 `--no-random-sleep-on-renew` 重试，
输出 `Congratulations, all simulated renewals succeeded` 和证书 `(success)`。
同一云助手命令后续重复演练遇到 300 秒执行超时，不能将整条命令标为成功；
上述首次重试成功及已签发的生产证书仍有效。本项目续期 service 曾运行完成，Result=success。
目前 HTTPS 仍代理旧中转；新版中转程序、私有环境文件迁移尚未执行。
先在手机导出备份并安装新版 APK 验证 AI/语音，再切换新版中转、关闭 8000。
排查材料见 `ALIYUN-NETWORK-TICKET.md`。2026-09-20 00:26 已提交阿里云工单
`00085S9EWE`。工程师认为与访问 Cloudflare 的跨境链路有关，建议 TCP 路由测试、
客户端代理或替代 CA；未承诺修复时间。目前工单尚未反馈本次恢复结果。

目标：`App → https://8.163.98.62:443 → Nginx → 127.0.0.1:8000 → AI/百度`。
已有 ECS 继续使用，无需重装系统。SQLite 账单仍在手机本地。

## 1. 安全组

在阿里云 ECS 安全组增加 TCP 80 和 443 入方向规则，来源 `0.0.0.0/0`。
80 用于证书验证，443 用于 App。暂时保留 8000，待新版 App 验证后关闭。
SSH 22 保留自己的管理入口，勿把自己锁在服务器外。

## 2. 上传脚本

在本机 PowerShell 进入项目目录后执行；SSH 密码只在终端提示中输入：

```powershell
ssh root@8.163.98.62 'mkdir -p /root/yiyuji-upgrade'
scp relay/server.js relay/deploy-aliyun.sh relay/setup-https-ip.sh relay/migrate-legacy-env.py root@8.163.98.62:/root/yiyuji-upgrade/
ssh root@8.163.98.62
```

首次 SSH 连接应核对实例主机指纹。也可在阿里云 Workbench 终端上传、执行这些文件。

## 3. 先配置 HTTPS，保留原中转

在服务器执行：

```sh
cd /root/yiyuji-upgrade
bash setup-https-ip.sh 8.163.98.62
```

可在 IP 后附加证书联系邮箱。脚本安装 Nginx/Certbot，申请 IP 证书并配置每六小时检查续期。
签发失败时不要关闭 8000，原中转仍可用。需先确保安全组及服务器防火墙允许 80/443。
成功标准是 `https://8.163.98.62/health` 返回正常且没有证书错误。

## 4. 迁移服务端配置及程序

```sh
python3 migrate-legacy-env.py
```

脚本只在服务器本地读取旧 systemd 配置，写入权限 600 的 `/etc/yiyuji/relay.env`，不会输出密钥，不覆盖已有文件。
旧值曾进入源码历史，需在服务商控制台换新，再在服务器更新该文件。

**先安装使用 HTTPS 的新版 App 并验证 AI/语音，再切换服务监听范围**：

```sh
bash deploy-aliyun.sh
curl --fail https://8.163.98.62/health
systemctl is-active yiyuji-relay nginx yiyuji-cert-renew.timer
```

新版中转只监听本机，使用专用用户运行，日限额见 README；此步骤之后旧 HTTP 8000 客户端将无法连接。
HTTPS 和新版 App 确认可用后，删除安全组对公网的 8000 放行规则。
部署前可将旧 `/opt/yiyuji/relay.js` 与 `/etc/systemd/system/yiyuji-relay.service` 私密备份用于回退；旧 unit 包含凭据，不要复制到公开仓库。

## 5. 新 APK

本项目正式包使用固定配置打包（配置只含下面三个公开参数）：

```powershell
./tools/build_release.ps1 -Flutter D:/flutter/bin/flutter.bat
```

等价手动命令：

```powershell
flutter build apk --release --dart-define=LLM_RELAY_URL=https://8.163.98.62/v1 --dart-define=ASR_RELAY_URL=https://8.163.98.62 --dart-define=LLM_MODEL=agnes-2.5-flash
```

APK 不内置上游密钥。HTTPS 和服务端 AI 探测已通过，手机端 AI/语音仍需实测。
旧包为 debug 签名：先导出账单 JSON，再卸载旧包、安装新正式签名包并恢复。

参考：[阿里云安全组](https://www.alibabacloud.com/help/zh/ecs/user-guide/start-using-security-groups)、[Certbot IP 证书官方说明](https://letsencrypt.org/2026/03/11/shorter-certs-certbot/)。
IP 证书有效期约 6 天，续期任务与 Nginx 证书重载是部署的必要部分。
