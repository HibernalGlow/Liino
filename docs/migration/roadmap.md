# liino 分阶段迁移路线图（Migration Roadmap）

遵循“先验证基座与内存基线、再整理 Rust Core、后分端迁移、最后统一产品体验”的原则，所有阶段必须通过真实编译与设备运行验证后方可推进。

## 当前状态（2026-11-14）

- **实施细节以 ADR 为准**：`docs/architecture/adr/` 记录已定决策，未拍板项与推荐默认值见 `docs/architecture/grilling.md`。
- **上游复用原则**：除了 **蓝牙** 和 **Flutter UI**，其余能力一律交给 MicYou。源码以 submodule 放在 `vendor/micyou` / `vendor/micyou-ios`，**直接 path 依赖，不复制**；机制与映射见 `upstream-reuse.md`。
- Phase 1 已完成 macOS arm64 验证：Release `.app` 可编译运行，GUI 空闲 RSS 约 90–125 MB，关闭窗口后 GUI 进程退出、`liino-daemon` 存活。数据见 `docs/memory/baseline.md`。
- Phase 2 正在从“复制迁移”切换为“直接依赖”：`packages/liino_api` 已依赖 `micyou-core` 并通过 Android arm64 链接验证；早期复制件待逐步删除。
- Phase 3 / Phase 4 只有骨架：Android 平台桥是 MethodChannel 桩，daemon 尚无托盘、登录自启与真实音频链路。
- 下一优先事项：把 daemon/移动端会话切到 `micyou-core` 的 discovery + transport，再接托盘、Android AudioRecord 与蓝牙。

## Phase 0：技术调研与基座克隆（已完成）
- 对比 LocalSend、RustDesk 与官方 FRB v2 模板，确定 **LocalSend** 为基座。
- 克隆 `localsend/localsend` 至项目目录，配置只读 `upstream` 与本地 `liino` 分支。
- 审计 `MicYou-Dev/MicYou` 的 Rust Workspace 与 Android 端代码。
- **交付物**：`base-project-selection.md`、`overview.md`、`current-code-audit.md`、`roadmap.md`。

## Phase 1：最小 Flutter + Rust + FRB 工程与内存基线（macOS 已完成）
- 在 `liino` 分支建立最小可运行工程：Flutter 客户端 + `liino_core` Rust Crate + FRB v2 桥接 + Material 3 Expressive 主题与核心状态面板雏形。
- 验证当前可用目标平台的 **Release 编译**（macOS arm64 已通过；Windows / Android 在对应环境补测）。
- 测量并记录真实 Release 进程内存基线（启动、空闲、关闭窗口、daemon 常驻），写入 `docs/memory/baseline.md`。

## Phase 2：Rust Core 整理与解耦（策略调整为直接依赖 vendor）
- **不再复制 MicYou 代码**：`exclude = ["vendor"]` + path 依赖，直接使用 `micyou-core` / `micyou-protocol` / `micyou-audio` / `micyou-infer`。
- 已用 `crates/arboard-shim`（`[patch.crates-io]`）解决 `arboard` 无 Android 后端的问题；Android `minSdk` 因 AAudio 提到 26。
- `packages/liino_api` 已直接依赖 `micyou-core`，host 与 `aarch64-linux-android` 均通过编译/链接。
- 早期复制件 `crates/liino-{protocol,infer,audio-core,engine}` 保留单元测试作为回归资产，待 daemon / FRB 全部切到 vendor 后删除。
- 待办：把 daemon 与移动端的 discovery、TCP/UDP 会话、audio pipeline 切到 `micyou-core`；补 Windows / Linux 目标平台编译验证。

## Phase 3：Android 端迁移（进行中）
- 使用 Flutter UI 替换 MicYou 原 `composeApp`（当前 `apps/liino_app` 已具备仪表盘 / 设备 / DSP 三页雏形）。
- 已生成 `android/` 平台工程并打通构建链路：`tool/build_android_rust.sh` 交叉编译 `libliino_api.so` 到 `jniLibs/arm64-v8a`，`flutter build apk --release --target-platform android-arm64` 产出 17.7 MB APK。
- `MainActivity` 已实现 `dev.liino.app/android_audio` MethodChannel（权限、前台服务启停），`AudioForegroundService` 以 `microphone` 类型常驻；真机验证 FRB 加载与前台服务生命周期通过。
- 仍缺：`AudioRecord` 采集 → Rust 编码/传输的真实音频链路，以及设备发现与会话建立（当前两端 UI 无法互相发现）。
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

