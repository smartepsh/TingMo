## Why

macOS 缺少一个轻量级、始终可用的智能听写转录输入工具。虽然系统自带听写功能，但它缺乏灵活的转录控制、多引擎支持、上下文感知的 LLM 智能纠正能力，以及自定义快捷键触发。我们需要一个原生 macOS 应用 **TingMo（听墨）**，提供插件化的语音转文字体验，支持本地和远程多种语音识别引擎，并通过 LLM 对转录结果进行智能纠正，最终将结果直接输入到当前焦点位置。

## What Changes

- 创建一个全新的 macOS 原生应用 TingMo（Swift/SwiftUI），以菜单栏常驻方式运行
- 音频输入设备管理：设备枚举、UID 持久化、优先级排序、在线状态监听、录音中设备断开处理
- 插件化语音识别引擎：本地（WhisperKit 多模型、Apple Speech Framework、Parakeet）+ 远程（Groq、ElevenLabs 等），支持自定义下载源和本地模型导入
- Config Preset 配置预设：将引擎、语言、LLM、设备选择模式打包为可切换的预设组合，iCloud 同步（API Key 除外）
- 用户自定义词典/术语表，提升专业术语、人名等识别准确度
- 可选的 LLM 智能纠正后处理，支持多种 API 格式（OpenAI compatible、Anthropic 等），用户自配 API Key
- 丰富的上下文获取能力：选中文本、输入框内容、窗口信息、剪贴板、Active App 全文读取、屏幕截图
- 全局快捷键（短按 toggle + 长按 press-to-record + ESC 取消）+ 应用排除列表 + CLI / AppleScript 外部调用
- 转录结果直接进入剪贴板并自动粘贴，无需手动确认，剪贴板恢复时间可配
- 转录历史记录，方便回查复制，保留最近音频文件支持重试
- 三种听写状态提示 UI 模式：Notch 刘海 / 顶部居中 / 独立浮窗，跟随焦点显示器
- 首次启动引导 + 多语言 UI（中文/英文）
- 开源项目（GPL v3），独立分发（Sparkle + GitHub Releases）+ App Store 双轨

## Capabilities

### New Capabilities

- `audio-device`: 音频输入设备管理，枚举系统设备、UID 持久化记忆历史设备、优先级排序、设备在线状态监听、录音中断开处理（本地管理，不走 iCloud）
- `speech-engine`: 插件化语音识别引擎管理，支持本地模型列表（WhisperKit、Apple Speech、Parakeet）和远程 API（Groq、ElevenLabs），支持自定义下载源和本地模型导入，音频格式适配
- `config-preset`: 配置预设包管理，将引擎、语言、LLM 参数、设备选择模式打包为可切换的预设组合；支持三种设备选择模式（跟随系统/指定设备/优先级列表）；App Store 版通过 iCloud 同步（API Key 除外，存本地 Keychain）；后期支持按 Active App 自动切换预设、预设导入导出
- `global-hotkey`: 全局快捷键注册与监听，支持短按 toggle 和长按 press-to-record 双模式（按下即录音）、ESC 取消录音、自定义快捷键、应用排除列表，以及 CLI / AppleScript 外部调用
- `context-awareness`: 上下文获取能力，包括选中文本、输入框内容、窗口信息、剪贴板、Active App 全文读取（Accessibility API）、屏幕截图，Accessibility 优先 + 截图兜底
- `dictionary`: 用户自定义词典/术语表，全局管理、Config Preset 引用；LLM 开启时注入 prompt 上下文，LLM 关闭时做文本替换兜底；iCloud 同步
- `llm-correction`: 可选的 LLM 智能纠正后处理，支持 OpenAI compatible 和 Anthropic API 格式，用户自配 API Key、model、prompt 等参数，LLM 配置由 Config Preset 管理
- `text-injection`: 将最终文本写入剪贴板并自动粘贴到当前活跃输入位置，剪贴板恢复延迟可配
- `history`: 转录历史记录，方便用户回查和复制过往转录结果；保留最近少量音频文件支持转录重试；提供存储管理和清理功能
- `status-indicator`: 听写状态提示 UI，支持三种显示模式：Notch 刘海嵌入（默认）、顶部居中、独立浮窗；跟随焦点显示器；兼作错误提示显示
- `onboarding`: 首次启动引导（权限授权、引擎选择下载、快捷键设置）和多语言 UI 支持（中文/英文）
- `menubar-ui`: 菜单栏常驻应用 UI，提供状态显示、Config Preset 切换、历史记录入口、设置入口

### Modified Capabilities

<!-- 无现有能力需要修改，这是一个全新项目 -->

## Impact

- **新增代码**: 整个 macOS 应用项目（Swift Package + Xcode）
- **系统权限**: 麦克风权限、辅助功能权限（Accessibility）、语音识别权限、屏幕录制权限（截图上下文，可选）
- **依赖**: WhisperKit（本地 Whisper + Parakeet）、Apple Speech Framework、CGEvent API、Sparkle（自动更新）
- **系统要求**: macOS 13.0+ (Ventura)，支持 Apple Silicon 和 Intel
- **开源许可**: GPL v3
- **分发方式**: 独立分发（Sparkle + GitHub Releases）+ App Store
