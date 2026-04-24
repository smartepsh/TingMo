# TingMo 架构说明

> **状态：** 活文档，技术决策变动时更新。
> **最近修订：** 2026-04-23

## 1. 技术栈

- **语言：** Swift 5.9+
- **UI：** SwiftUI（菜单栏、设置、引导、列表）+ AppKit（Notch、全局键盘、Accessibility、文本注入等系统桥接）
- **工程组织：** Xcode 项目（`TingMo.xcodeproj`）；依赖通过 SPM
- **最低系统：** macOS 13.0 (Ventura)
- **架构：** Apple Silicon + Intel
- **应用类型：** LSUIElement（无 Dock 图标）

## 2. 模块划分

代码按 capability 分目录，一个 capability 一个目录：

```
TingMo/
  TingMoApp.swift               # 入口 + 组合根
  Assets.xcassets
  Localizable.xcstrings
  TingMo.entitlements

  AudioDevice/                  # 输入设备枚举、UID 持久化、优先级、在线状态
  Hotkey/                       # CGEvent tap、双模式、排除列表、CLI、AppleScript
  Permission/                   # 麦克风、Accessibility、语音识别、屏幕录制
  SpeechEngine/                 # 引擎协议 + 各引擎实现 + 音频捕获 + 格式适配
  StatusIndicator/              # Notch / 顶部居中 / 浮窗
  Onboarding/                   # 首启引导 + 步骤组件

  # —— 即将新增（M1+）——
  TextInjection/                # 剪贴板保存/恢复 + Cmd+V 模拟
  MenuBar/                      # 菜单栏下拉内容
  Pipeline/                     # 端到端管线协调（hotkey → 捕获 → 引擎 → 纠正 → 注入 → 历史）

  # —— 后续里程碑 ——
  Context/                      # M3（Accessibility 基础项）
  LLM/                          # M3
  ConfigPreset/                 # M4（极简版），完整版 1.0 后
  KnowledgeBase/                # M5（历史存储 + 向量索引 + 检索 + 管理 UI）
  UIRefresh/                    # M6（范围待定）
  Updater/                      # M7（Sparkle）

  # —— 1.0 后 ——
  Dictionary/                   # 自定义词典（1.0 后）
  History/                      # 完整历史 UI + 音频重试（1.0 后；M4 已有基础存储）
  Sync/                         # iCloud 同步（1.0 后）
```

## 3. 关键设计决策

### 3.1 插件化语音引擎

统一 `SpeechEngine` 协议，所有引擎实现同一接口（start / stop / streaming 支持标志 / 支持语言）。用户在模型列表中浏览、下载、切换。

- **本地：** WhisperKit、Parakeet（待 Argmax SDK）
- **远程：** Groq、ElevenLabs（用户自配 API Key）
- **流式策略：** 支持流式的引擎显示实时预览；否则显示等待状态。
- **不支持 Apple Speech Framework** — 精度/标点/定制能力不足以承载 TingMo 的核心体验，不纳入引擎矩阵。

### 3.2 模型来源与导入

WhisperKit 模型默认从 HuggingFace 下载（散文件夹），支持：

- 自定义 `downloadBase`（镜像 URL）
- 本地导入：校验 `.mlmodelc` 后 **拷贝** 到 `~/Library/Application Support/TingMo/Models/`（拷贝而非引用，避免原始文件被删）
- 模型不走 iCloud（体积过大），每台设备独立管理

### 3.3 音频设备：本地管理 + UID 持久化

通过 CoreAudio 枚举，使用 `kAudioDevicePropertyDeviceUID` 持久化记住设备。同一物理设备断开重连后 UID 不变。设备列表与优先级每台机器独立，不走 iCloud。

录音中设备断开：立即停止、状态 UI 通知用户、已录音频正常走转录流程。**不做自动切换。**

### 3.4 Config Preset（M4 极简）

M4 只存 LLM 配置（provider / endpoint / key-ref / model / prompt / temperature）。用户只有一个默认 Preset，先不承担引擎/语言/设备模式，也不绑定知识库。

1.0 后再扩展为完整 Preset（引擎、语言、设备选择模式、活跃词典/知识库分片），届时再引入菜单栏切换器、数量限制、iCloud 同步（API Key 不同步）。

### 3.5 知识库（Knowledge Base）

LLM 纠正前的个性化语义检索层。定位取代自定义词典，成为 v1 的个性化主力。

**已定方向**
- 纯本地，不上云，不做跨用户聚合
- 默认关闭，依赖 LLM 已开启
- 数据源：历史转录（自动积累）、用户手动笔记、外部文件导入（Markdown / 纯文本）
- 在 LLM 纠正前注入：当前转录作为 query，检索相关片段拼入 prompt

**M5 v1 技术决策**

1. **Embedding 模型：Apple `NLEmbedding` sentence embedding**
   - 首版使用 Natural Language 框架内置 `NLEmbedding.sentenceEmbedding(for:)`，按文本语言选择 `.simplifiedChinese` / `.english`，无法判断或不可用时降级到可用语言，再不行只走 FTS5 关键字检索。
   - 理由：零模型下载、零打包体积、纯本地、Swift 集成成本最低，适合 M5 先验证“历史纠正可检索注入”的产品闭环。
   - 暂不采用 `bge-small-zh-v1.5` / `multilingual-e5-small` 作为首版默认：效果潜力更高，但需要 Core ML/ONNX 转换、tokenizer 集成、模型下载与版本迁移；列为 M5 后续质量升级。

2. **向量存储：SQLite BLOB + 应用内 cosine 扫描**
   - 每条知识库片段保存一个归一化 `Float32` 向量 BLOB，维度和 embedding 模型版本随记录保存。
   - 查询时读取同模型/同维度向量，在 Swift 中做 dot product / cosine，取 top-K。M5 预期 1K-100K 条，首版接受线性扫描，用真实 dogfood 数据再决定是否升级。
   - 暂不采用 `sqlite-vec` / SQLite `vec1` / USearch 作为首版默认：它们能带来 ANN 或更快 KNN，但会增加扩展加载、二进制分发、沙盒与迁移复杂度；保留为规模上来后的替换层。

3. **原文存储：单个 SQLite 数据库**
   - 数据库位于 `~/Library/Application Support/TingMo/KnowledgeBase/knowledge.sqlite`。
   - 首版直接使用系统 `sqlite3` C API，避免为 M5-1 引入新的 SPM 依赖；如果后续管理 UI/观察需求复杂，再引入 GRDB。
   - 表结构分三层：`kb_entries`（原始条目与元数据）、`kb_chunks`（可检索片段）、`kb_embeddings`（向量与模型版本）。同时维护 `kb_chunks_fts` FTS5 表用于关键字召回和 embedding 不可用时的兜底。

4. **检索策略：语义优先，FTS 兜底**
   - Query 使用“当前转录 + 非敏感上下文摘要”，但当前转录权重最高；上下文只取应用名、窗口标题、选中文本等短字段，避免把整段输入框内容变成噪声。
   - 默认 `topK = 5`，每条片段最多 600 字符，总注入预算 2,000 字符。
   - 语义检索只返回超过阈值的结果；阈值首版设为 `0.35`，dogfood 后调整。若 embedding 不可用或结果不足，用 FTS5 `rank` 补足。
   - 去重按 `entryID` 做，同一条历史最多注入一个最高分片段。

5. **Prompt 注入格式：作为 user message 的上下文块**
   - 不改用户自定义 system prompt，避免知识库内容与行为指令混在一起。
   - 通过 `LLMContextItem.Kind.knowledgeBase` 注入到现有 `LLMCorrectionPrompt.userMessage` 的上下文区，格式为“历史纠正片段：原文 → 纠正后；来源应用；时间”。
   - 知识库片段只作为纠错参考，提示语强调“仅在有帮助时使用”，避免把旧内容误当作当前输入。

6. **索引生命周期**
   - 历史转录保存后立即写入 `kb_entries`，并排队异步 chunk + embedding。
   - 首次启用知识库时批量补索引已有未索引条目；进度 UI 在 M5-5 管理页展示，M5-1/M5-2 先提供状态字段。
   - `embeddingModelID` 或 `embeddingRevision` 改变时，旧向量标记为 stale，后台重建；原文永远不因向量重建失败而丢失。

7. **隐私/合规边界**
   - 标记为敏感的上下文不入库；文本若匹配密码/API key/token 等模式，默认跳过知识库保存。
   - 管理 UI 必须提供清空知识库、删除单条、禁用来源类型。M5 不做 iCloud 同步；向量和原文都只留本机。

8. **升级路径**
   - 如果 dogfood 显示 Apple sentence embedding 对中文专名召回不足，优先新增可下载 Core ML embedding 模型（候选 `bge-small-zh-v1.5` 或 `multilingual-e5-small`）。
   - 如果线性扫描在 100K 条附近不可接受，再将 `VectorIndex` 协议实现替换为 `sqlite-vec` 或 USearch；数据库 schema 已把原文、chunk、embedding 拆开，便于迁移。

### 3.6 LLM 纠正：可选后处理

- 协议化：`LLMProvider`
- 支持 OpenAI compatible + Anthropic；Ollama 等本地推理通过 localhost OpenAI-compat 接入
- 用户自配：endpoint、API Key、model、system prompt、temperature
- 默认关闭

### 3.7 上下文策略：Accessibility 基础项

v1 仅实现前 4 项（Accessibility 基础 + 剪贴板）：

1. 选中文本（Accessibility）
2. 当前输入框内容（Accessibility）
3. 窗口标题 / 应用名（Accessibility）
4. 剪贴板（NSPasteboard）

**1.0 后：**

5. Active App 全文深读（Accessibility，1–2 秒超时）
6. 屏幕截图（需屏幕录制权限，需多模态 LLM）

### 3.8 全局快捷键：双模式

- 默认 Option+D；按下瞬间立即录音
- 松开时根据持续时长判断：
  - `< 300ms` → toggle 模式，录音继续，下次短按停止
  - `≥ 300ms` → push-to-record，松开即停
- toggle 模式下 ESC 可取消录音（仅在录音激活期间全局拦截）
- 通过 CGEvent tap 实现，支持应用排除列表
- 不用 Carbon（已废弃）或 NSEvent global monitor（只能监听不能拦截）

### 3.9 文本注入：剪贴板 + Cmd+V 模拟

- 写剪贴板 → CGEvent 模拟 Cmd+V → 按可配延迟恢复原剪贴板（默认 500ms）
- 粘贴前保存完整 pasteboard（所有数据类型）
- 注意：剪贴板管理器工具可能捕获临时写入（已知 trade-off）

### 3.10 状态提示 UI

- Notch（默认）：嵌入刘海，波形动画 + 可选预览文字
- 顶部居中：无刘海设备降级
- 浮窗：完整状态 + 转录预览
- 多显示器时跟随焦点窗口
- 错误提示走状态 UI，**不用系统通知**

### 3.11 分发双轨

- **独立分发：** 代码签名 + 公证，Sparkle 自动更新（appcast on GitHub），GPL v3
- **App Store：** 沙盒兼容子集，iCloud 同步付费功能，App Store 管理更新
- App Store 沙盒与 Accessibility / CGEvent tap 冲突，部分能力仅独立版提供

### 3.12 SwiftUI + AppKit 混合

- SwiftUI：菜单栏、设置、引导、列表
- AppKit：Notch 窗口、CGEvent 键盘、Accessibility 读取、文本注入
- LSUIElement = YES（无 Dock 图标）

## 4. 非目标（技术维度）

- 不自建云端后端
- 不内嵌 LLM 运行时（llama.cpp、MLX 等）
- 不支持 iOS / iPadOS
- 不做富文本编辑器

## 5. 关键风险与权衡

| 风险 | 缓解 |
|------|------|
| 多引擎架构复杂度 | 先做 Apple Speech（M1）+ WhisperKit（M2），远程渐进补齐 |
| Accessibility 深读在 Electron/浏览器慢 | 1–2 秒超时，降级截图 |
| 屏幕录制权限用户不愿授权 | 仅截图兜底功能依赖，可选、不强制 |
| 剪贴板冲突（剪贴板管理器） | 可接受的已知权衡 |
| 快捷键冲突 | 自定义绑定 + 应用排除 |
| HuggingFace 下载慢 | 自定义 `downloadBase` + 本地导入 |
| LLM 纠正延迟 | 用户自行决定是否启用 |
| Parakeet 无中文支持 | 模型列表标注语言；中文场景推荐 Whisper |
| App Store 沙盒限制 | 双轨分发：核心能力走独立版 |
| 知识库 embedding 模型体积 | 选用小模型（bge-small 级别，~100MB Core ML）；必要时独立下载而非打包 |
| 知识库检索延迟叠加在 LLM 之上 | top-K 小（默认 5），本地向量检索毫秒级；总链路仍以 LLM 网络延迟为主 |
| 知识库噪声（低质量历史污染检索） | 管理 UI 允许删除 / 禁用来源；后续可加相关性阈值过滤 |

## 6. 开发工作流

- 任务管理：**fp**（`fp issue`、`fp comment`、`fp tree`、`fp bs`）
- 计划文档：`docs/PRD.md`（产品）、`docs/ROADMAP.md`（里程碑）、`docs/architecture.md`（本文）
- 特性探索：`fp bs`（brainstorm），必要时落地到 `docs/capabilities/<name>.md`
- 历史遗留 OpenSpec 资料：`docs/archive/openspec-legacy/`（仅供参考，不再更新）
