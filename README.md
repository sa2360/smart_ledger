# 一语记 · 智能收支记账（smart_ledger）

一句话，记好账。Flutter Android 应用，当前版本 `1.0.2+3`。

## 功能与数据流

- 手动记账：支出/收入、金额、分类、备注、日期时间；支持修改、删除和常用模板。
- AI 文本记账：描述 → 模型拆单 → 用户核对并勾选 → 确认后批量入库。取消不会保存。
- 小票记账：相机/相册 → ML Kit 中文离线 OCR → 识别文本发送给模型 → 核对确认入库。
- 语音输入：16kHz/16bit/单声道 PCM，55 秒自动停止 → 百度语音识别 → 填入文本框，再由用户解析。
- 首页：今日/本月/全部筛选、按日分组、月收支、预算进度；本周支出超过前四周平均的 1.5 倍时提醒。
- 分析：本月/本年 AI 报告、分类占比、近六个月趋势；年度报告按全年明细汇总分类，不混用月度预算。
- AI 问答：以本月和上月账单为上下文，最多携带最近 8 条对话；回答由模型生成。
- 预算：支持切换月份，设置总预算及全部八类支出预算；AI 方案保存到下月，可切换查看。
- 周期记账：每天、每周、每月 1–28 日；启动、回到前台或首页刷新时补记，无独立后台定时任务。
  每日首次从当天开始；周/月首次从未过去的本周/本月目标日开始。执行后按 `last_run` 补齐遗漏周期。
  账单和执行日期在同一事务内更新；并发执行合并，不重复入账。旧版本已生成的重复账单不会自动删除。
- 搜索：关键词、分类、金额范围、收支类型和日期区间；每页 100 条，可加载全部匹配结果。
  数量和收支合计对应全部匹配账单，日期包含开始及结束当天；关键词中的 `%`、`_` 和反斜杠按字面匹配。
- 分类纠错：最多保存 20 条备注关键词映射，作为下次 AI 文本解析参考；常用模板最多 12 条。
- 深色/浅色/跟随系统、CSV 导出、JSON 备份恢复。

## 数据与隐私

账单持久化在手机本地 SQLite `smart_ledger.db`，无账户或云同步。
**使用 AI 时，相关消费文字、小票 OCR 文本、月度/年度明细或问答所需的最近两个月账单会发送到所选 AI 服务。**
语音识别会将录音发送给百度，使用中转时先经过自建服务器。小票照片由端上 OCR 处理。
自定义 API Key 保存在设备 SharedPreferences，并随请求发送至用户配置的接口用于鉴权。
仅手动记账、查询、预算和本地统计可完全离线使用。

数据库版本 3：

| 表 | 内容 |
|---|---|
| `bill_table` | 金额、类型（0 支出/1 收入）、分类、备注、时间 |
| `budget_table` | 月份、总预算、JSON 分类预算 |
| `recurring_table` | 周期规则、上次执行日期、启用状态 |
| `restore_preferences` | 恢复时的临时持久化任务，偏好恢复完成后清除 |

JSON 备份版本 2 包含三张业务表、模板、纠错记录、主题及自定义接口地址/模型名；**不含 API Key、语音 token、设备标识和聊天历史**。
恢复前验证全部记录，三张业务表在单个事务中替换。偏好恢复任务与业务数据同事务提交，中断后下次启动继续。
恢复 v2 后切回内置模式，自定义 Key 需重新输入；兼容 v1 备份，v1 不覆盖本机偏好。

## 代码结构

- `lib/main.dart`：初始化、主题和四个 Tab；`IndexedStack` 保留页面，`common/global.dart` 通知数据刷新。
- `lib/db/`、`lib/models/`：SQLite 和账单/预算/周期实体。
- `lib/pages/`：首页、记账、账单详情、分析、对话、预算、搜索、周期和设置页面。
- `lib/services/`：AI/语音、周期执行、模板纠错、配置、导出与备份。
- `relay/server.js`：无第三方依赖的 Node.js 转发服务；部署说明见 [relay/README.md](relay/README.md)。
- `test/`：数据库事务、恢复、周期执行、页面筛选、统计、预算月份、主题和 AI 流程回归测试。

本轮检查和后续验证事项见 [项目进度记录](PROJECT_PROGRESS.md)。

## AI 配置

当前阿里云服务器 `8.163.98.62` 的专用升级步骤见 [服务器升级说明](relay/ALIYUN-MIGRATION.md)。

现有生产服务地址已保存在 `config/production.json`，只含公开地址和模型名，不含上游密钥。正式打包使用固定脚本，避免遗漏 AI/语音配置：

```powershell
./tools/build_release.ps1 -Flutter D:/flutter/bin/flutter.bat
```

更换服务器时更新该配置文件。通用 HTTPS 中转的手动构建示例：

```powershell
flutter build apk --release --dart-define=LLM_RELAY_URL=https://your-domain.example/v1 --dart-define=ASR_RELAY_URL=https://your-domain.example --dart-define=LLM_MODEL=agnes-2.5-flash
```

`LLM_RELAY_URL` 非空时，内置 AI 不要求客户端保存上游 Key。语音使用 `ASR_RELAY_URL/asr`。
未注入服务的安装包仍可离线记账，并在「我的」配置 HTTPS 的 OpenAI 兼容接口、模型和 API Key；内置语音则不可用。
兼容旧版直连参数 `LLM_BASE_URL`、`LLM_API_KEY`、`LLM_MODEL`、`BAIDU_API_KEY`、`BAIDU_SECRET_KEY`，但直连密钥会进入安装包，不用于公开发行。
生产安装包禁止明文 HTTP，服务必须提供有效 HTTPS。

## 开发、验证与签名

本机已安装 Flutter 3.47.3 / Dart 3.13.3、JDK 17、Android SDK；依赖锁要求 Dart >=3.12、Flutter >=3.44。
Windows PowerShell 本机命令（其他机器相应修改路径）：

```powershell
$env:ANDROID_HOME = 'D:/android-sdk'
$env:ANDROID_SDK_ROOT = 'D:/android-sdk'
$env:JAVA_HOME = 'D:/jdk17/jdk-17.0.20.1+1'
$env:PATH = 'D:/flutter/bin;' + $env:PATH
flutter pub get
flutter analyze
flutter test
node --test relay/server.test.js
python tools/check_secrets.py
./tools/build_release.ps1 -Flutter D:/flutter/bin/flutter.bat -NoPub
```

正式构建读取 `android/key.properties`，样例为 `android/key.properties.example`；缺少正式签名时构建明确失败，不回退到 debug 签名。
本工作区已生成独立的 `android/release-keystore.jks` 和 `android/key.properties`，均已被 Git 忽略。请将这两个文件一并私密备份，后续版本保持相同签名。
**旧安装包使用 debug 签名，不能被新正式签名包直接覆盖。先在旧 App 导出 JSON 备份，再卸载旧版、安装新版并恢复。**
产物：`build/app/outputs/flutter-apk/app-release.apk`。摄像头、OCR 和麦克风仍需真实 Android 设备验证。

## 已泄露凭据处理

旧部署文件曾提交上游密钥。当前文件已改为环境变量，旧值仍可能存在于 Git 历史和旧构建产物中。
需要在 Agnes / 百度控制台撤销旧值、生成新值，并更新服务器私有环境文件后重启；本地改源码不能撤销服务商凭据。
历史清理应在轮换完成后与仓库协作者协调执行，不能用删除当前文件代替轮换。
