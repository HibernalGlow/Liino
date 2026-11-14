# liino 分阶段迁移路线图（Migration Roadmap）

遵循“先验证基座与内存基线、再整理 Rust Core、后分端迁移、最后统一产品体验”的原则，所有阶段必须通过真实编译与设备运行验证后方可推进。

## 当前状态（2026-11-14）

- Phase 1 已完成 macOS arm64 验证：Release `.app` 可编译运行，GUI 空闲 RSS 约 90–125 MB，关闭窗口后 GUI 进程退出、`liino-daemon` 存活。数据见 `docs/memory/baseline.md`。
- Phase 2 的 Crate 迁移与单元测试已落地（116 个测试通过），但 Android / Windows / Linux 的目标平台编译尚未实机验证。
- Phase 3 / Phase 4 只有骨架：Android 平台桥是 MethodChannel 桩，daemon 尚无托盘、登录自启与真实音频链路。
- 下一优先事项：接入原生托盘与登录自启，并补齐 Android 前台服务与 AudioRecord。

## Phase 0：技术调研与基座克隆（已完成）
- 对比 LocalSend、RustDesk 与官方 FRB v2 模板，确定 **LocalSend** 为基座。
- 克隆 `localsend/localsend` 至项目目录，配置只读 `upstream` 与本地 `liino` 分支。
- 审计 `MicYou-Dev/MicYou` 的 Rust Workspace 与 Android 端代码。
- **交付物**：`base-project-selection.md`、`overview.md`、`current-code-audit.md`、`roadmap.md`。

## Phase 1：最小 Flutter + Rust + FRB 工程与内存基线（macOS 已完成）
- 在 `liino` 分支建立最小可运行工程：Flutter 客户端 + `liino_core` Rust Crate + FRB v2 桥接 + Material 3 Expressive 主题与核心状态面板雏形。
- 验证当前可用目标平台的 **Release 编译**（macOS arm64 已通过；Windows / Android 在对应环境补测）。
- 测量并记录真实 Release 进程内存基线（启动、空闲、关闭窗口、daemon 常驻），写入 `docs/memory/baseline.md`。

## Phase 2：Rust Core 整理与解耦（代码迁移完成，跨平台待验证）
- 已迁移并重构 `liino-protocol`、`liino-audio-core`、`liino-engine`、`liino-platform`，并额外落地 `liino-infer` 与 `liino-daemon`。
- 已剥离桌面 UI 假设：核心 Crate 不依赖 `arboard`、`open`、`notify-rust`、`global-hotkey` 或 Tauri。
- 已为有界缓冲区（Jitter Buffer、RingBuffer）、Opus 解码与传输校验建立单元测试；`session.rs` 覆盖会话绑定与包校验状态机。
- 待办：Windows / Linux / Android 目标平台 `cargo check` 与实机编译；清理 `liino-infer` 的 clippy warning。

## Phase 3：Android 端迁移（进行中）
- 使用 Flutter UI 替换 MicYou 原 `composeApp`（当前 `apps/liino_app` 已具备仪表盘 / 设备 / DSP 三页雏形）。
- `AndroidAudioBridge` 已定义 MethodChannel 协议（权限、前台服务启停），尚缺 Kotlin 侧 `ForegroundService` 与 `AudioRecord` 实现。
- 保留稳定的 Android `ForegroundService` 与原生麦克风权限/AudioRecord 适配，逐步将传输、Opus 与 DSP 切换至 `liino-engine`。
- 对比旧版 Android APK 进行延迟、功耗与长时运行内存回归测试。

## Phase 4：Windows / macOS 桌面端迁移与 Daemon 落地（进行中）
- `liino-daemon` 已实现：Unix Socket / Named Pipe IPC、`ping`/`get_status`/角色与传输切换/启停/优雅退出。
- 已验证关闭主窗口后 Flutter GUI 进程完全退出、daemon 与 socket 继续存活。
- GUI 侧已实现 daemon 自动拉起（优先使用 App 内嵌的 `Contents/Resources/liino-daemon`）与重启复用，无需手动启动。
- 待办：原生系统托盘、登录自启；Windows VB-CABLE / WASAPI、macOS BlackHole / CoreAudio Tap、Wi-Fi、USB（ADB / usbmux）与蓝牙传输的真实音频链路。
- 验收仍需确认：关闭窗口后音频服务不中断（依赖上一条的真实音频链路）。

## Phase 5：统一产品体验与双向能力
- 落地 `RoleMode { Auto, Sender, Receiver }` 与 `DeviceCapabilities` 能力探测。
- 统一设备发现列表、会话管理、音频监控、设置系统、快捷键、菜单栏与系统通知。
- 实现断线重连恢复与插件按需加载。

## Phase 6：稳定性与性能回归
- 长时音频流传输（数小时级）无界增长检测。
- 桌面端 GUI 反复启动/关闭内存泄漏测试。
- 系统休眠唤醒恢复、网络切换与蓝牙稳定性测试。
- 完成各平台安装包构建并确认旧版前端可安全下线。

