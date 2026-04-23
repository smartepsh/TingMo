## Context

TingMo（听墨）是一个全新的 macOS 原生应用项目，目标是提供智能语音听写转录输入功能。应用以菜单栏常驻方式运行，用户通过全局快捷键（或 CLI/AppleScript）触发听写，语音通过可选的本地或远程引擎转录，可选经 LLM 智能纠正后，结果直接写入剪贴板并自动粘贴到当前输入位置。

项目使用 Swift 和 SwiftUI 构建，采用插件化架构支持多种语音识别引擎和 LLM provider。开源（GPL v3），付费策略后续确定。

## Goals / Non-Goals

**Goals:**
- 插件化语音识别：本地模型列表（用户自选下载/导入）+ 远程 API（用户自配 Key）
- 音频输入设备管理：设备枚举、UID 持久化、优先级排序、在线状态监听
- Config Preset 配置预设：引擎、语言、LLM、设备选择模式打包为可切换组合
- 可选 LLM 智能纠正，支持上下文感知
- 丰富的上下文获取（Accessibility + 截图兜底）
- 全局快捷键（短按 toggle + 长按 press-to-record）+ ESC 取消 + 应用排除列表 + CLI / AppleScript 调用
- 三种状态提示 UI 模式（Notch / 顶部居中 / 独立浮窗），跟随焦点显示器
- 转录结果直接进剪贴板 + 自动粘贴，无需手动确认，剪贴板恢复延迟可配
- 转录历史记录，方便回查复制，保留最近音频文件支持重试
- 首次启动引导 + 多语言 UI（中文/英文）
- 菜单栏常驻，资源占用最小化
- iCloud 同步 Config Preset（App Store 版，API Key 除外）

**Non-Goals:**
- 不自建云端服务（所有 API 调用由用户自配）
- 不内嵌 LLM 运行时（用户通过 Ollama 等外部工具自行运行本地 LLM，TingMo 通过 OpenAI compatible API 连接）
- 不实现完整的文本编辑器功能
- 不支持 iOS/iPadOS — 仅 macOS
- 不实现语音命令控制（如 "删除上一句"）
- 不做自动应用适配（第一阶段通过用户 Config Preset 手动切换场景，后期支持按 App 自动切换）

## Decisions

### 1. 使用 Swift Package Manager 项目结构

使用 SPM 管理项目，配合 Xcode 打开。代码更易于版本控制，减少 .xcodeproj 冲突。

**替代方案**: 纯 Xcode 项目 — .xcodeproj 文件在版本控制中噪音大。

### 2. 插件化语音识别引擎架构

提供统一的引擎协议（protocol），所有引擎实现同一接口。用户在模型列表中浏览、下载、切换引擎。

**本地引擎：**
- **WhisperKit** — Whisper 系列模型（tiny/base/small/medium/large），Core ML 加速，支持流式
- **Apple Speech Framework** — 零下载、低延迟流式识别，作为轻量备选
- **Parakeet**（通过 Argmax SDK / CoreML）— 英文专用，精度高于 Whisper，等 Argmax SDK 原生支持后集成

**远程引擎：**
- **Groq**（Whisper API）、**ElevenLabs** 等 — 录完传音频文件，等结果返回
- 用户自配 API Key

**流式策略：** 引擎支持流式则显示实时预览（Apple Speech、WhisperKit），不支持则显示等待状态。

**替代方案**: 只用单一引擎 — 灵活性不够，不同场景对精度/速度/语言的需求不同。

### 3. 语音识别模型下载与导入

WhisperKit 模型默认从 Hugging Face 下载（散文件夹，非 zip），支持两种替代获取方式：
- **自定义下载源** — 通过 WhisperKit 的 `downloadBase` 参数配置镜像 URL
- **本地导入** — 用户通过文件选择器或拖拽导入模型文件夹，TingMo 校验 `.mlmodelc` 文件完整性后**拷贝**到 `~/Library/Application Support/TingMo/Models/` 目录

拷贝而非引用，避免用户删除原始文件后模型不可用。模型文件不走 iCloud 同步（体积过大），每台设备独立下载或导入。

### 4. 音频设备管理：本地管理 + UID 持久化

音频输入设备通过 CoreAudio 枚举，使用 `kAudioDevicePropertyDeviceUID`（基于硬件序列号等信息生成）持久化记住设备。同一物理设备断开重连后 UID 不变，可被识别。设备列表和优先级排序在每台机器上独立管理，不通过 iCloud 同步。

录音过程中设备断开时：立即停止录音、通过状态 UI 通知用户、已录音频正常走转录流程。不做自动切换到下一个设备。

### 5. Config Preset 替代 Prompt 预设

原有的"Prompt 预设"升级为 Config Preset（配置预设包），将引擎、语言、LLM 参数（provider、endpoint、model、prompt、temperature）、设备选择模式、活跃词典选择打包为一个完整的可切换配置。

**设备选择模式**三选一：跟随系统默认 / 使用本地指定设备 / 按本地优先级列表自动选择。Config Preset 只存策略（"system" / "specified" / "priority"），具体设备列表由每台机器的 audio-device 模块管理。

**替代方案**: 保持 Prompt 预设只管 prompt — 不同场景需要的不仅是 prompt 不同，引擎、语言、设备都可能不同，单独切换太繁琐。

### 6. Config Preset iCloud 同步策略

Config Preset 通过 iCloud 同步时，同步所有配置字段（名称、引擎偏好、语言、LLM endpoint/model/prompt/temperature、设备选择模式），**但 API Key 不同步**，存在每台设备的本地 Keychain 中。音频设备列表和优先级也不同步，由每台设备本地管理。

**原因**: Apple 明确建议不要使用 iCloud 存储密码类凭证。新设备同步下来 Preset 后，用户只需在本地补填 API Key 即可使用。

### 7. 不内嵌 LLM 运行时

LLM 纠正步骤不内嵌 llama.cpp 等本地推理引擎。用户如需本地 LLM，通过 Ollama 等外部工具运行，TingMo 通过 OpenAI compatible API（localhost 或内网/公网地址）连接。

**原因**: TingMo 定位是听写工具，不是 LLM runtime。内嵌会导致包体积暴增、与语音识别引擎争夺 GPU/内存资源、增加维护成本。

### 8. 用户自定义词典：双重纠正策略

用户可创建多份词典（术语表），包含专业术语、人名、缩写及其常见误识别形式。词典全局管理，Config Preset 引用（选择启用哪几份）。

**双重策略：**
- **LLM 开启时** — 活跃词典的术语注入 LLM prompt 上下文，由 LLM 语义理解后纠正，不做文本替换（避免双重纠正）
- **LLM 关闭时** — 基于词典中定义的误识别模式做文本替换兜底

词典通过 iCloud 同步（App Store 版），体积小、无敏感信息。

### 9. LLM 智能纠正作为可选后处理

转录完成后，可选将结果交给 LLM 纠正。支持多种 API 格式：
- **OpenAI compatible**（覆盖 OpenAI、Groq、Ollama、各种中转站）
- **Anthropic**
- 后续可扩展更多

用户自配：API endpoint、API Key、model、system prompt、temperature 等参数。默认关闭，用户自行开启。

### 10. 上下文获取策略：Accessibility 优先 + 截图兜底

为 LLM 纠正提供上下文，按优先级：
1. **选中文本** — Accessibility API
2. **当前输入框内容** — Accessibility API
3. **当前窗口标题/应用名** — Accessibility API
4. **剪贴板内容** — NSPasteboard
5. **Active App 全文上下文** — Accessibility API 深度读取（终端输出、浏览器网页、AI 聊天记录等），设 1-2 秒超时
6. **屏幕截图** — 作为兜底，Accessibility 读不到或超时时使用，需要多模态 LLM

### 11. 全局快捷键：短按 toggle + 长按 press-to-record + ESC 取消

同一个快捷键（默认 Option+D）支持两种录音模式。按下瞬间立即开始录音（不等阈值），松开时根据按住时长判断行为：
- **短按**（< 300ms）：切换模式，录音继续，下次短按停止
- **长按**（≥ 300ms）：松开即停止录音

短按 toggle 模式下，按 ESC 可取消录音，丢弃已录音频，不走转录流程。ESC 仅在录音激活期间作为全局键拦截，其他时候透传。

通过 CGEvent tap 监听全局键盘事件。支持应用排除列表——在指定应用中不拦截快捷键。

**替代方案**:
- Carbon RegisterEventHotKey — 可用但已废弃
- NSEvent.addGlobalMonitorForEvents — 只能监听不能拦截

### 12. 文本注入使用剪贴板 + Cmd+V 模拟

转录（+ 可选 LLM 纠正）完成后，直接写入剪贴板，通过 CGEvent 模拟 Cmd+V 粘贴。无需用户确认/编辑环节。

粘贴前保存用户剪贴板内容（包括所有数据类型），粘贴后按用户可配的延迟时间恢复（默认 500ms）。

### 13. 转录历史记录

保存所有转录结果，主要显示 LLM 纠正后的最终文本，方便用户回查和复制（剪贴板恢复后仍可从历史复制）。

音频文件仅保留最近少量（默认 3 次，可配），主要目的是支持网络失败等场景的转录重试。不长期保留音频。提供存储管理界面，用户可查看各部分占用空间并清理。

### 14. 三种状态提示 UI 模式

- **Notch 刘海模式**（默认）— 嵌入摄像头缺口区域，显示波形动画，空间允许时也显示预览文字
- **顶部居中模式** — 无刘海设备降级方案，贴在屏幕顶部正中间，显示波形动画
- **独立浮窗模式** — 完整的状态显示 + 转录预览文字

用户在设置中选择。无刘海设备自动降级为顶部居中。多显示器时跟随焦点窗口所在的显示器。

错误提示（设备断开、网络失败等）也通过状态 UI 显示，不使用系统通知。

### 15. 外部调用接口

- **CLI** — `tingmo start`、`tingmo stop`、`tingmo toggle` 等
- **AppleScript** — 支持 macOS 快捷指令、Alfred、Raycast 等调用

### 16. 应用架构：SwiftUI + AppKit 混合

菜单栏、设置界面使用 SwiftUI 构建。Notch UI、全局快捷键、文本注入、Accessibility 读取等系统交互使用 AppKit 桥接。应用设置为 LSUIElement（无 Dock 图标）。

### 17. 首次启动引导 + 多语言 UI

首次启动显示 onboarding wizard，引导用户逐步完成：麦克风权限 → Accessibility 权限 → 屏幕录制权限（可选）→ 选择并下载语音引擎 → 设置全局快捷键。用户可跳过，后续在设置中补全。

应用界面支持中文（简体）和英文，跟随 macOS 系统语言，其他语言不支持时降级为英文。后续可扩展更多语言。

### 18. 独立分发 + App Store 双轨

**独立分发版：**
- App Store 沙盒限制与 Accessibility API、CGEvent tap 等核心功能冲突
- 代码签名 + 公证（Notarization）
- Sparkle 自动更新：appcast.xml 托管在 GitHub（Pages 或 raw URL），更新包放在 GitHub Releases，检测到新版本时提示用户确认下载
- 开源（GPL v3）

**App Store 版：**
- iCloud 同步 Config Preset、多 Preset 支持等付费功能
- 更新由 App Store 管理

## Risks / Trade-offs

- **[引擎集成复杂度]** 多引擎插件化增加架构复杂度 → 先实现 WhisperKit + Apple Speech 两个本地引擎，远程引擎后续逐步添加
- **[上下文读取效率]** Accessibility API 深度读取在复杂应用（浏览器、Electron）中可能很慢 → 设置 1-2 秒超时，超时降级为截图
- **[屏幕截图权限]** 截图上下文需要屏幕录制权限，用户可能不愿授权 → 作为可选功能，不强制
- **[辅助功能权限]** 应用需要多项系统权限 → 首次启动引导用户逐步授权
- **[剪贴板冲突]** 粘贴注入会临时覆盖用户剪贴板 → 粘贴前保存、粘贴后恢复（恢复延迟可配），剪贴板管理器可能捕获临时写入
- **[全局快捷键冲突]** 快捷键可能与其他应用冲突 → 支持自定义快捷键 + 应用排除列表
- **[模型下载慢]** Hugging Face 在部分地区下载慢 → 支持自定义下载源 + 本地模型导入
- **[LLM 纠正延迟]** LLM API 调用增加等待时间 → 用户自行决定是否开启，非流式引擎本身就需要等待
- **[Parakeet 中文不支持]** 目前 Parakeet 不支持中文 → 在模型列表中标注语言支持范围，中文场景推荐 Whisper 系列
