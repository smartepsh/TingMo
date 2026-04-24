# TingMo 路线图

> **状态：** 活文档。里程碑为垂直切片——每个里程碑结束时，应用都应是可用状态。
> **当前重点：** M3（LLM 纠正 + 基础上下文）。

## 图例

- ✅ 已完成
- 🟡 部分 / 仅骨架
- ❌ 未开始

## M0 — 基础（存量工作）

重构前 `main` 分支已有的工作。无新增计划，仅供对齐。

- ✅ Xcode 项目、LSUIElement 外壳、entitlements、应用图标
- ✅ 音频设备模块：枚举、UID 持久化、优先级列表、在线监听、断开处理、管理 UI
- ✅ 全局快捷键：双模式（toggle + push-to-record）、ESC 取消、排除列表、CLI、AppleScript
- ✅ 权限管理 + 状态 UI
- ✅ 状态提示：Notch / 顶部居中 / 浮窗；波形动画；多显示器跟焦
- ✅ 首启引导外壳（欢迎 → 权限 → 占位 → 完成）
- ✅ 远程引擎适配骨架（Groq / ElevenLabs + 失败重试）
- 🟡 WhisperKit 引擎：结构外壳，缺 SPM 依赖与真实转录（M1 补齐 tiny 模型）
- 🟡 Parakeet 引擎：占位
- 🟡 Config Preset：仅数据模型占位
- 🟡 设置界面：87 行占位实现
- ⚠️ Apple Speech 引擎：存量代码，**M1 中清除**（不再作为支持引擎）

## M1 — 最小可听写（WhisperKit tiny）

**成果：** 按快捷键 → 说话 → 文本粘贴到光标处。端到端跑通，本地单引擎（WhisperKit tiny），无附加功能。

管线：hotkey → 音频捕获 → WhisperKit tiny → 写剪贴板 + Cmd+V → 剪贴板恢复。

- 集成 WhisperKit（SPM 依赖 + tiny 模型下载/加载，最小实现）
- 清除 Apple Speech 相关代码（引擎文件 + 权限项 + Info.plist 描述）
- 文本注入模块：剪贴板保存/恢复 + CGEvent Cmd+V，可配恢复延迟
- DictationPipeline 协调器：hotkey → 捕获 → 引擎 → 注入
- 菜单栏下拉 v1：状态显示、打开设置、退出
- 端到端错误提示走状态 UI（无麦克风 / 模型未就绪 / 空转录 / 推理失败）
- 作者本机可 dogfood

**明确推迟：** LLM、上下文、历史、Preset、词典、知识库、多引擎/多模型、远程引擎、自定义下载源、本地模型导入。

## M2 — 多模型 + 远程引擎

**成果：** 用户可按场景选择最佳模型与引擎；本地多模型 + 远程 API 都可用。

- WhisperKit 多模型支持（tiny 之外补 base / small / medium / large）
- 模型下载管理：HF 默认 + 自定义 `downloadBase` + 进度 UI
- 本地模型导入：文件选择器 + 拖拽、校验 `.mlmodelc`、拷贝到 App Support
- 远程引擎（Groq、ElevenLabs）全量对接，API Key 存 Keychain
- 设置内引擎/模型切换器 + 多语言 + 引擎-语言兼容性校验
- Parakeet：等 Argmax SDK，保留占位 "coming soon"

## M3 — LLM 纠正 + 基础上下文

**成果：** 转录文本经用户自选 LLM 做上下文感知纠正。

- LLMProvider 协议 + OpenAI-compat 适配 + Anthropic 适配
- 纠正管线：转录 + 上下文 → LLM → 纠正后文本
- API Key 存储（Keychain），provider 维度的 model/prompt/temperature 配置
- 上下文感知 v1：Accessibility — 选中文本、当前输入框、窗口标题 + 应用名、剪贴板；密码字段检测与排除
- 上下文聚合器（优先级 + 开关）
- **推迟：** Active App 深读、截图兜底（→ 1.0 后）

## M4 — Preset

**成果：** 将用户的 LLM 配置沉淀为可复用的 Preset，先保持范围克制。

- **极简 Preset：** 仅承载 LLM 配置
- 设置内管理 Preset 基础配置：provider / endpoint / key-ref / model / prompt / temperature
- 默认 Preset 与迁移：现有 LLM 配置升级为默认 Preset
- Preset 配置用于纠正管线，不影响 M2 的引擎/模型切换
- **推迟：** 完整 CRUD、多 Preset 菜单栏切换、按应用自动切换、Preset ↔ 词典 ↔ 知识库分片绑定（→ 1.0 后）

## M5 — 知识库纠正 🎯

**成果：** 用户过往的转录、纠正与笔记，成为 LLM 纠正时的个性化上下文源。

**为什么做这个：** 比静态自定义词典更强——能覆盖用户独特的用词习惯、专有名词、口语化表达，且随使用自动积累，无需手动维护。

### 功能（骨架，技术选型已定）
- **历史转录存储**：本地数据库，存原始转录 + 纠正结果 + 元数据
- **向量索引**：本地 embedding（模型与存储方案待调研），增量更新
- **检索管线**：当前转录作为 query，取 top-K 相关片段注入 LLM prompt
- **手动添加笔记/片段**：管理 UI 添加
- **外部导入**：Markdown / 纯文本批量导入
- **管理 UI**：条目浏览、搜索、删除、来源禁用、存储占用
- **隐私：** 向量 + 原文仅本地，不上传
- **默认关闭**：用户主动开启，且 LLM 已开启

> 技术决策见 `docs/architecture.md` §3.5：M5 v1 使用 Apple `NLEmbedding`、SQLite 原文/FTS/向量 BLOB、应用内 cosine 检索，后续按 dogfood 数据再升级模型或向量索引。

### 推迟到 1.0 后
- iCloud 向量同步
- Per-Preset 知识库分片（M4 不绑定知识库）

## M6 — UI 调整

**成果：** 预留一个独立 UI 调整里程碑；具体范围待后续设计/体验审阅后补充。

- 待定义

## M7 — 发布

**成果：** 真实用户可安装使用。

- 代码签名 + 公证流程
- Sparkle 集成，appcast 托管于 GitHub Pages，发布打包
- App Store 构建轨道（沙盒兼容子集）
- SMAppService 开机自启
- 崩溃 & 诊断基线（opt-in）
- 1.0 发布

## 路线图之外（1.0 后再议）

- Config Preset 完整 CRUD + 菜单栏切换器 + 数量限制
- 自定义词典（术语表 + 双策略）— 知识库已部分覆盖其用途
- 三种设备选择模式（system / specified / priority）的完整接入
- Preset ↔ 词典 ↔ 知识库分片绑定
- Active App 全文深读（Accessibility）
- 截图兜底上下文（屏幕录制权限）
- iCloud 同步：Preset / 词典 / 知识库向量
- 从历史重试转录 + 音频保留 + 存储管理 UI
- 按应用自动切换 Preset
- Preset 导入/导出文件
- 更多 LLM provider
- 更多本地化语言
