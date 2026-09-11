# 一语记 · 智能收支记账 App（smart_ledger）

> 一句话，记好账。

基于《智能收支记账APP 软件设计说明书》实现的 **Flutter 移动端 App**（Android）。
核心亮点：自然语言 AI 记账 + 小票 OCR 拍照记账 + 月度 AI 消费分析 + 智能预算规划。

## 技术架构（与设计书一致）

| 分层 | 实现 |
|---|---|
| UI 展示层 | Flutter Material 3（首页 / AI 分析 / 预算 / 我的 四个 Tab + 记账页三模式） |
| 业务逻辑层 | 记账逻辑、月度统计、AI 请求封装（`lib/services/llm_service.dart`）、OCR 调用、预算判断 |
| 数据持久层 | 本地 SQLite（sqflite），`bill_table` / `budget_table` 与设计书第四章完全一致 |
| 外部服务层 | 内置 AI 模型服务（默认，构建时注入）+ 用户自定义 OpenAI 兼容模型 + 端上离线 OCR（ML Kit 中文） |

## 功能清单

- **手动记账**：金额、收/支、分类（餐饮/交通/购物/娱乐/学习/医疗/居住/其他/工资/兼职/理财/红包）、备注、时间
- **AI 自然语言记账**：输入「今天午饭25，奶茶15，打车12」，AI 自动拆分多条账单、识别金额、自动分类、生成备注后批量入库
- **小票拍照记账**：拍照/相册选图 → 端上离线 OCR（google_mlkit_text_recognition 中文模型）→ 小票全文交 AI 提取消费条目 → 入库
- **账单管理**：今日/本月/全部切换、按日分组统计、修改、删除
- **月度 AI 分析**：整月账单明细全部拼入 Prompt，AI 输出消费报告（结构分析 + 省钱建议）+ 下月各分类预算方案，预算方案可一键应用
- **预算管理**：月度总预算 + 分类预算，可视化进度条、超支红色提醒
- **AI 记账助手对话**：直接用自然语言查账——「我这个月奶茶花了多少？」，AI 基于最近两个月真实账单回答，支持多轮追问
- **近 6 个月收支趋势**：AI 分析页内置收支折线图，月度走势一目了然
- **周期自动记账**：房租、订阅等固定收支设定周期（每天/每周/每月）自动入账，错过若干天会自动补记
- **数据表**：`bill_table` / `budget_table` / `recurring_table`，本地 SQLite 持久化
- **分类占比饼图**（fl_chart）

## 数据库

本地 SQLite 共三张表：`bill_table`（账单）、`budget_table`（预算）、`recurring_table`（周期记账配置）。

## AI 接入（内置 + 自定义双模式）

- **内置模式（默认，开箱即用）**：构建时通过 `--dart-define` 注入内置 AI 服务
  （接口地址 / 模型名称 / API Key），用户拿到 App 即可直接使用 AI 功能，无需任何配置。
- **自定义模式**：用户在「我的」页切换，自行填写 OpenAI 兼容接口地址、模型名称和 API Key，
  支持「测试连接」；未配置 Key 时，本地功能（手动记账、账单、预算、统计）全部可用。

构建命令示例：

```
flutter build apk --release \
  --dart-define=LLM_BASE_URL=https://api.agnes.ai/v1 \
  --dart-define=LLM_API_KEY=sk-你的Key \
  --dart-define=LLM_MODEL=agnes-2.5-flash
```

## 构建 / 安装

环境：Flutter 3.47.3（`D:\flutter`）、JDK 17（`D:\jdk17\jdk-17.0.20.1+1`）、Android SDK（`D:\android-sdk`，platform 36 / build-tools 36.0.0 & 36.1.0）。

```
flutter pub get
flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

数据全部存于手机本地 SQLite（`smart_ledger.db`），不上传任何第三方服务器。

## 目录结构

```
lib/
├── main.dart                  # 应用入口 + 底部导航框架
├── common/global.dart         # 全局刷新信号
├── db/database_helper.dart    # SQLite 建表 + CRUD（bill_table / budget_table）
├── models/
│   ├── bill.dart              # 账单实体
│   └── budget.dart            # 预算实体（分类预算 JSON 存储）
├── services/
│   ├── llm_service.dart       # LLM 封装：JSON 提取、自然语言解析、小票解析、月度分析
│   └── settings_service.dart  # AI 配置：内置 / 自定义双模式，本地存储
├── pages/
│   ├── home_page.dart         # 首页：统计面板 + 预算进度 + 按日分组账单
│   ├── add_bill_page.dart     # 记账页：手动 / AI 文本 / 小票拍照 三模式
│   ├── bill_edit_page.dart    # 账单修改 / 删除
│   ├── ai_analysis_page.dart  # AI 月度报告 + 下月预算方案一键应用
│   ├── budget_page.dart       # 预算设置 + 使用进度 + 超支提醒
│   ├── profile_page.dart      # AI 服务配置（内置 / 自定义双模式）
│   └── widgets/               # 分类图标、账单条目、饼图等公共组件
└── test/widget_test.dart      # 启动冒烟测试
```
