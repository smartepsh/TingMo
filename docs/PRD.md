# TingMo 听墨 — 产品需求文档（PRD）

> **状态：** 活文档，产品方向变动时更新。
> **最近修订：** 2026-04-23

## 1. 愿景

一款轻量、常驻菜单栏的 macOS 智能听写工具。按下快捷键即可说话，转录结果（可选经 LLM 纠正）自动粘贴到当前光标处。不绑定任何云服务，UI 极简，尽量不打断用户工作流。

## 2. 目标用户

写作量大的 macOS 重度用户——开发者、作者、研究者、学生——希望语音输入能够：

- 比打字更快，且不离开当前应用
- 比系统听写更准，尤其对专业术语
- 完全由用户掌控：自选引擎、自配 API Key、自建词典

## 3. 核心原则

1. **插件化，不做选择替代** — 用户自选引擎（本地/远程）与 LLM
2. **上下文感知纠正** — 利用屏幕信息修正歧义转录
3. **零摩擦捕获** — 快捷键 → 说话 → 粘贴，无确认环节
4. **菜单栏原生** — 无 Dock 图标，无主窗口
5. **用户拥有自己的密钥** — 无 TingMo 云端服务
6. **开源** — GPL v3，透明、可自行构建

## 4. 功能范围

### 4.1 范围内

**捕获**
- 全局快捷键：短按 toggle + 长按 push-to-record + ESC 取消
- 自定义快捷键绑定 + 按应用排除列表
- CLI (`tingmo start|stop|toggle`) 与 AppleScript 入口
- 音频输入设备管理：枚举、基于 UID 持久化、优先级列表、在线状态监听、录音中断开处理

**转录**
- 插件化 speech-engine 协议
- 本地引擎：WhisperKit（多模型）、Parakeet（英文专用，待 Argmax SDK 支持）
- 远程引擎：Groq、ElevenLabs（用户自配 API Key）
- 模型来源：HuggingFace 默认 / 自定义 `downloadBase` / 本地文件夹导入（拷贝至 App Support）
- 引擎支持流式时显示实时预览；否则显示等待状态
- **不使用 Apple Speech Framework**——放弃系统内建听写，以保证跨场景精度与自定义能力

**纠正**
- 可选 LLM 后处理（OpenAI compatible + Anthropic），用户自配 endpoint/key/model/prompt
- **知识库纠正**（核心差异点）：用户过往转录、纠正结果、手动笔记、导入文本作为向量索引的语义检索源；LLM 纠正前按当前转录检索 top-K 相关片段注入 prompt；自动随使用积累，无需手动维护；所有数据本地存储
- LLM 上下文来源：选中文本、当前输入框、窗口标题+应用名、剪贴板；Active App 全文深读与屏幕截图兜底为 1.0 后功能

**输出**
- 写入剪贴板 + CGEvent 模拟 Cmd+V（无确认环节）
- 粘贴前保存用户剪贴板，粘贴后按可配延迟恢复
- 转录历史（本地数据库），支持复制；保留少量音频文件支持重试

**UI**
- 菜单栏 Extra：状态、Config Preset 切换、当前设备、历史入口、设置、退出
- 状态提示：Notch（默认）/ 顶部居中（无刘海降级）/ 独立浮窗；跟随焦点显示器
- 首启引导：权限 → 引擎选择/下载 → 快捷键设置；可跳过
- 本地化：简体中文 + 英文，跟随系统语言，其他语言降级为英文

**个性化**
- Config Preset 独立里程碑：先仅承载 LLM 配置 + 知识库开关；完整 Preset（引擎/语言/设备模式/词典/多 Preset 切换）列为 1.0 后目标
- API Key 始终存本地 Keychain，不走 iCloud

**分发**
- 独立分发：代码签名 + 公证，Sparkle 自动更新（appcast 托管于 GitHub）
- App Store 版：沙盒兼容子集 + iCloud 同步
- macOS 13+ (Ventura)，Apple Silicon + Intel

### 4.2 非目标

- 不做 TingMo 托管后端 — 所有 API 凭证由用户提供
- 不内嵌 LLM 运行时 — 用户通过 Ollama 等工具 + OpenAI compatible endpoint 接入
- 不做粘贴前的富文本编辑 / 审阅 UI
- 不支持 iOS / iPadOS
- 不实现语音命令控制（如"删除上一句"）
- 知识库不上云，不做跨用户聚合——纯本地个性化
- v1 不做完整 Preset CRUD / 多 Preset 切换 / 按应用自动切换
- v1 不做自定义词典（能力被知识库部分覆盖）

## 5. 系统权限

- **麦克风** — 必需
- **辅助功能（Accessibility）** — 必需（快捷键捕获、文本注入、上下文读取）
- **屏幕录制** — 可选，仅用于截图兜底上下文（1.0 后）

> 不再使用 Apple Speech Framework，因此不需要"语音识别"权限。

## 6. 分发与授权

- 协议：**GPL v3**
- 独立分发：Sparkle + GitHub Releases
- App Store：独立构建，含 iCloud 同步功能

## 7. 成功指标（方向性）

- 从快捷键按下到文本粘贴的耗时（P50）— 流式引擎目标 < 2s
- 纠正质量 — 主观评估，通过 dogfooding + 用户反馈
- 首启引导完成率 — 完成引导用户数 / 启动用户数
- 引擎使用分布 — 本地 vs 远程（若未来加入匿名、选择性遥测）

## 8. 待定问题

- App Store 版定价策略（TBD）
- 遥测政策（当前：无）
- 如何在不撑爆配置 UI 的前提下，支持 OpenAI-compat + Anthropic 之外的 LLM provider
- Parakeet 中文支持 — 受上游阻塞；中文场景继续使用 Whisper

## 9. 术语表

- **知识库（Knowledge Base）** — 本地语义检索源，内容包括历史转录、用户纠正、手动笔记、导入文本。LLM 纠正前通过 embedding 检索 top-K 注入 prompt。纯本地，默认关闭。
- **Config Preset（极简版）** — 独立里程碑；先仅承载 LLM 配置 + 知识库开关，非完整 Preset。完整版（含引擎/语言/设备/词典切换）列为 1.0 后目标。
- **设备选择模式** — `system` | `specified` | `priority`。当前 v1 按系统默认设备或 audio-device 模块优先级运行，完整三模式打通列为 1.0 后目标。
- **Active App 全文深读** — 通过 Accessibility API 对前台应用做完整文本抽取（1.0 后目标）。
- **双模式快捷键** — 同一个键位，按松开时的持续时长（< 300ms 与 ≥ 300ms）判断是 toggle 还是 push-to-record。
