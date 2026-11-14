# liino 分阶段迁移路线图（Migration Roadmap）

遵循“先验证基座与内存基线、再整理 Rust Core、后分端迁移、最后统一产品体验”的原则，所有阶段必须通过真实编译与设备运行验证后方可推进。

## Phase 0：技术调研与基座克隆（已完成）
- 对比 LocalSend、RustDesk 与官方 FRB v2 模板，确定 **LocalSend** 为基座。
- 克隆 `localsend/localsend` 至项目目录，配置只读 `upstream` 与本地 `liino` 分支。
- 审计 `MicYou-Dev/MicYou` 的 Rust Workspace 与 Android 端代码。
- **交付物**：`base-project-selection.md`、`overview.md`、`current-code-audit.md`、`roadmap.md`。

## Phase 1：最小 Flutter + Rust + FRB 工程与内存基线（当前阶段）
- 在 `liino` 分支建立最小可运行工程：Flutter 客户端 + `liino_core` Rust Crate + FRB v2 桥接 + Material 3 Expressive 主题与核心状态面板雏形。
- 验证当前可用目标平台的 **Release 编译**（macOS arm64；Windows / Android 在对应环境补测）。
- 测量并记录真实 Release 进程内存基线（启动、空闲、交互切换、持续运行 RSS/Footprint），写入 `docs/memory/baseline.md`。

## Phase 2：Rust Core 整理与解耦
- 从 MicYou 迁移并重构 `liino-protocol`、`liino-audio-core`、`liino-engine`、`liino-platform`。
- 剥离桌面 UI 假设（`arboard`、`open` 等），确保全部核心 Crate 支持 Android / iOS / macOS / Windows / Linux 条件编译。
- 为有界缓冲区（Jitter Buffer、RingBuffer）、Opus 编解码与协议状态机建立单元测试。

## Phase 3：Android 端迁移
- 使用 Flutter UI 替换 MicYou 原 `composeApp`。
- 保留稳定的 Android `ForegroundService` 与原生麦克风权限/AudioRecord 适配，逐步将传输、Opus 与 DSP 切换至 `liino-engine`。
- 对比旧版 Android APK 进行延迟、功耗与长时运行内存回归测试。

## Phase 4：Windows / macOS 桌面端迁移与 Daemon 落地
- 实现独立 `liino-daemon`（Rust Host + 原生系统托盘 + Named Pipe / Unix Socket IPC + Flutter 子进程管理）。
- 迁移并验证 Windows VB-CABLE / WASAPI、macOS BlackHole / CoreAudio Tap、Wi-Fi、USB（ADB / usbmux）与蓝牙传输。
- 验证关闭桌面窗口后 Flutter 进程完全退出、内存彻底释放且音频服务不中断。

## Phase 5：统一产品体验与双向能力
- 落地 `RoleMode { Auto, Sender, Receiver }` 与 `DeviceCapabilities` 能力探测。
- 统一设备发现列表、会话管理、音频监控、设置系统、快捷键、菜单栏与系统通知。
- 实现断线重连恢复与插件按需加载。

## Phase 6：稳定性与性能回归
- 长时音频流传输（数小时级）无界增长检测。
- 桌面端 GUI 反复启动/关闭内存泄漏测试。
- 系统休眠唤醒恢复、网络切换与蓝牙稳定性测试。
- 完成各平台安装包构建并确认旧版前端可安全下线。
