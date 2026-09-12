# 一语记 · 中转服务部署指南（DomCloud 免费版）

中转服务（`relay/server.js`）持有 Agnes / 百度的 API Key，替 App 转发请求。
**APK 中不包含任何 Key**，Key 只存在服务端。

## 一、在 DomCloud 创建网站

1. 打开 https://my.domcloud.co
2. 首页点 **「Create a new website」**（⚠️ 不是 "Create a new server"，那个弹窗是把外部服务器接入面板用的，直接关掉）
3. 免费计划（Free），子域名随意，比如 `yiyuji-你的名字`，记住最终域名（形如 `yiyuji-xxx.domcloud.id`）
4. 创建后进入该站点的管理页，找到 **「Deployment」**（部署）页面，把里面的 YAML 内容替换为下面的脚本

## 二、部署 YAML

把下面内容粘贴到部署脚本里（替换全部内容），**把三个 Key 换成你自己的**：

```yaml
features:
  - node lts

nginx:
  root: public_html/public
  passenger:
    enabled: "on"
    app_start_command: env AGNES_KEY=你的AgnesKey BAIDU_API_KEY=你的百度APIKey BAIDU_SECRET_KEY=你的百度SecretKey node relay.js

commands:
  - commands:
      - mkdir -p public_html/public
```

然后先把 `relay/server.js` 上传到网站的 `public_html/relay.js`：

- 方式 A：管理页的 **File Manager**（文件管理）里上传
- 方式 B：SSH 登录后，把文件内容粘贴进去：
  `nano ~/public_html/relay.js` → 粘贴 → Ctrl+O 保存 → Ctrl+X 退出

最后点 **Deploy / 部署** 执行脚本。

## 三、验证

浏览器打开 `https://你的域名/`，看到：

```json
{"ok":true,"service":"yiyuji-relay"}
```

即为成功。再用手机试一下 AI 功能即可。

## 四、限流说明

- 默认每 IP 每天 200 次请求、全局每天 2000 次（内存计数，重启清零）
- 调整：在 `app_start_command` 里加 `DAILY_LIMIT_PER_IP=次数`（0 为不限）

## 五、常见问题

| 现象 | 处理 |
|---|---|
| 打不开 502 | 查看管理页 Check → Process Logs，确认 relay.js 已上传到 public_html/ |
| 改了文件不生效 | SSH 里执行 `restart`，或面板重新 Deploy |
| AI 回复超时 | 免费版应用是「来请求时拉起」，首次请求慢属正常；月报生成较长，等一会再试 |

## 六、安全须知

- Key 写在部署 YAML / 环境变量里，存于服务端；不要把带 Key 的 YAML 发给别人
- 免费版流量 2GB/月（一次请求约 10KB，个人使用远用不完）
- 如果将来换服务器：同一个 `server.js` 在任何能跑 Node 的机器上 `node relay.js` 即可，App 只需改构建时的域名重新打包
