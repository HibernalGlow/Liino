# Phase 1 内存基线与编译验证记录（Memory Baseline）

> 最后更新：2026-11-14（补齐 macOS Release GUI 与 `liino-daemon` 实测）

## 1. 测试环境

- **主机平台**：macOS Apple Silicon (`darwin-arm64`)
- **Xcode**：`27.2`（`Build 27B52`，`/Applications/Xcode.app`）
- **Rust 工具链**：`cargo 1.99.1` / `rustc 1.99.1`（Homebrew；本机 `sccache` 在沙箱内不可用，采集时以 `RUSTC_WRAPPER=` 直连 rustc）
- **Flutter / Dart 工具链**：Flutter `3.47.4` / Dart `3.13.3`（mise 提供；仓库 `.fvmrc` 目标为 `3.47.9`，本机未安装 fvm，`3.47.x` 满足 `pubspec.yaml` 约束）
- **FRB**：`flutter_rust_bridge_codegen 2.12.0`
- **测量工具**：`ps -o rss`、`vmmap -summary`、`footprint -p`、`screencapture` + 目视核对

## 2. 已验证产物（macOS arm64 Release）

| 验证项 | 命令 / 产物 | 实测结果 |
| :--- | :--- | :--- |
| Rust 核心单元测试 | `cargo test -p liino-{protocol,audio-core,engine,platform,daemon,infer,core}` | **116 passed, 0 failed**（engine 78 / audio-core 33 / core 2 / daemon 2 / platform 1） |
| Clippy（`--all-targets`） | `cargo clippy ... --all-targets` | 无 `error`；仍有 `liino-infer` 数值代码的循环索引 / 精度类 warning 待清理 |
| FRB Release 动态库 | `cargo build --release -p liino_api` | `target/release/libliino_api.dylib` = **852 KB** |
| Flutter GUI Release | `flutter build macos --release` | `liino_app.app` = **23.0 MB**，内含 `Contents/Frameworks/libliino_api.dylib`（852 KB）与 `Contents/Resources/liino-daemon`（1.1 MB） |
| `liino-daemon` Release | `cargo build --release -p liino-daemon` | 二进制可启动，IPC socket 建在 `$XDG_RUNTIME_DIR` 或 `/tmp` |

## 3. Release 进程内存基线（2026-11-14 实测）

| 指标 | `liino_app` GUI（空闲，已连 daemon） | `liino-daemon`（空闲） |
| :--- | :--- | :--- |
| RSS | 启动约 **120 MB**，16 s 后稳定在 **90–125 MB** | **~1.7 MB** |
| `vmmap` Physical footprint | **111.9 MB**（peak **180.3 MB**） | **1.7 MB**（peak 1.7 MB） |
| `footprint` phys_footprint | **~53–58 MB**（peak ~185 MB） | **~1.2 MB** |
| 说明 | Flutter Engine + Impeller + Dart Heap 占绝对主体；Rust 核心以 dylib 形式常驻，自身贡献远小于 GUI 框架 | 纯 Rust + Tokio，无 GUI 依赖，适合常驻 |

### 3.1 IPC 与生命周期验证

| 验证项 | 方法 | 结果 |
| :--- | :--- | :--- |
| IPC 功能 | 经 Unix socket 依次发 `ping` / `get_status` / `set_role_mode` / `start_link` / `stop_link` | 全部返回预期 JSON；`get_status` 正确报告 `virtual_mic_installed=true`（BlackHole 2ch） |
| IPC 延迟 | 200 次 `ping` 往返 | p50 **0.02 ms**，p95 **0.03 ms**，max **0.04 ms**（本机回环） |
| GUI 自动拉起 daemon | 预先杀掉 daemon 与 socket 后启动 App | `DesktopIpcCoreGateway` 从 `Contents/Resources/liino-daemon` 拉起，~1 s 内 UI 显示“守护进程 IPC 已激活”，PID 与实际进程一致 |
| GUI 重启复用 daemon | 窗口关闭后再次启动 App | 仍只有 1 个 daemon 进程，复用原 PID，不重复拉起 |
| 关闭窗口释放 GUI | 关闭唯一窗口 | GUI 进程 **完全退出**，RSS 归零；daemon 进程与 socket 均存活 |
| daemon 优雅退出 | IPC `shutdown_daemon` | 进程退出并删除 socket 文件 |

## 4. 本轮发现并修复的问题（诚实记录）

1. **App Sandbox 阻断桌面端 IPC**：Flutter macOS 模板默认开启 `com.apple.security.app-sandbox`。沙箱内 `File('/tmp/liino-daemon.sock').existsSync()` 失败，`DesktopIpcCoreGateway` 会静默回退到进程内 FRB（UI 显示“进程内 FRB”而非“守护进程 IPC 已激活”）。
   - 处理：`DebugProfile.entitlements` / `Release.entitlements` 显式关闭 App Sandbox，并在 `Info.plist` 增加 `NSMicrophoneUsageDescription`。桌面端需要访问 daemon socket 与 CoreAudio/BlackHole，非 App Store 分发下这是必要取舍。
   - 验证：重新 `flutter build macos --release` 后，界面显示“守护进程 IPC 已激活 · 主机: macOS (PID …)”，PID 与 daemon 实际进程一致。
2. **桌面端缺少 daemon 拉起逻辑**：此前必须手动运行 `target/release/liino-daemon`，否则 GUI 只能走进程内 FRB，关闭窗口后音频会随 GUI 一起消失。
   - 处理：`DesktopIpcCoreGateway._ensureDaemon()` 在 socket 不可用时按 `LIINO_DAEMON_BIN` → `Contents/Resources/liino-daemon` → 工作区 `target/release/liino-daemon` 的顺序查找并 detached 启动，随后轮询 `ping` 直到就绪；Xcode 构建脚本把 daemon 复制进 `Contents/Resources` 并 ad-hoc 签名。
   - 验证：杀掉 daemon 后启动 App 会自动拉起；再次启动 App 时复用同一 PID。
3. **`liino-infer` 的 clippy deny 错误**：`fast_exp` 中 `LOG2E` 字面量触发 `clippy::approx_constant`，导致 `cargo clippy --all-targets` 直接失败；已改用 `std::f32::consts::LOG2_E`。
4. **daemon 未使用导入**：`use std::sync::Arc` 已移除。

## 5. 未能在本环境验证的平台与原因

1. **Android Release (`.apk` / `.aab`)**：本机未配置 Android SDK / NDK，未执行真机编译与 `adb shell dumpsys meminfo` 采集；`AndroidAudioBridge`（MethodChannel 桩）尚未配套 Kotlin `ForegroundService` / `AudioRecord` 实现。
2. **Windows / Linux Release**：需在对应目标系统或 CI Runner 上执行编译与 Private Working Set / RSS 采集；Windows Named Pipe 路径仅通过 `cfg` 代码审查，未实机运行。

## 6. 下一步基线补全清单

- [x] 安装完整 Xcode 后运行 `flutter build macos --release`，记录 GUI 启动、空闲、关闭销毁后的内存与 daemon 独立进程 RSS。
- [x] 验证关闭桌面窗口后 Flutter 进程完全退出、daemon 继续运行（Phase 4 关键行为）。
- [ ] 配置 Android SDK/NDK 后运行 `flutter build apk --release`，在真机上通过 `adb shell dumpsys meminfo` 记录启动、连接建立、音频传输与长时运行内存。
- [ ] 在 Windows 11 环境运行 `flutter build windows --release`，记录 Private Working Set 与 Named Pipe IPC 内存开销。
- [ ] 音频链路真正跑通后，补测“传输中”与“数小时级长时运行”的 RSS 增长曲线（Phase 6）。
