# Phase 1 内存基线与编译验证记录（Memory Baseline）

## 1. 测试环境

- **主机平台**：macOS Apple Silicon (`darwin-arm64`)
- **Rust 工具链**：`cargo 1.99.1` / `rustc 1.99.1`（Homebrew）
- **Flutter / Dart 工具链**：Flutter `3.47.4` / Dart `3.13.7` / `flutter_rust_bridge_codegen 2.12.0`
- **测量工具**：`/usr/bin/time -l`（采集真实 Release 进程的 `maximum resident set size` 与 `peak memory footprint`）

## 2. 已验证产物与实测数据（macOS arm64 Release）

| 验证项 | 命令 / 产物 | 实测结果 |
| :--- | :--- | :--- |
| Rust 核心单元测试 | `cargo test -p liino-core -p liino_api` | `liino-core` 2 passed, 0 failed；`liino_api` 编译通过 |
| FRB v2.12.0 绑定生成 | `flutter_rust_bridge_codegen generate` | 生成 `src/frb_generated.rs` (18 KB) 与 `lib/src/rust/*.dart` (4 个文件，共 ~26 KB) |
| FRB 动态库 Release 编译 | `cargo build --release -p liino-core -p liino_api` | `target/release/libliino_api.dylib` = **857 KB**；`libliino_api.a` = **10 MB** |
| Rust Core Release 进程基线 | `/usr/bin/time -l ./target/release/examples/mem_probe` | `maximum resident set size` = **1,867,776 B (~1.78 MiB)**；`peak memory footprint` = **1,261,952 B (~1.20 MiB)** |

## 3. 未能在本环境验证的平台与原因（诚实记录）

1. **macOS Flutter GUI Release (`.app`)**：本机仅安装了 `Xcode CommandLineTools`，未安装完整 `Xcode.app`（`xcodebuild` 报错），且当前沙箱对 `/opt/homebrew/share/flutter/bin/cache` 无写权限，因此未能执行 `flutter build macos --release` 及测量完整 Flutter GUI 进程 RSS / 关闭窗口后的内存释放。
2. **Android Release (`.apk` / `.aab`)**：本机未配置 Android SDK / NDK，未执行 Android 真机编译与内存采集。
3. **Windows / Linux Release**：需在对应目标系统或 CI Runner 上执行编译与 RSS/Private Working Set 基线采集。

## 4. 下一步基线补全清单（需在完整本机/CI 环境执行）

- [ ] 安装完整 Xcode 后运行 `flutter build macos --release`，分别记录 `liino_app` GUI 进程启动、空闲、切换页面、关闭销毁后的 RSS 与 `liino-daemon` 独立进程 RSS。
- [ ] 配置 Android SDK/NDK 后运行 `flutter build apk --release`，在真机上通过 `adb shell dumpsys meminfo` 记录初始启动、连接建立、音频传输与长时运行内存。
- [ ] 在 Windows 11 环境运行 `flutter build windows --release`，记录 Private Working Set 与 Named Pipe IPC 内存开销。
