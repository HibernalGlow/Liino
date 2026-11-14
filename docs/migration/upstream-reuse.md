# 上游复用与 vendor 同步（Upstream Reuse）

liino 的核心能力来自 [MicYou](https://github.com/MicYou-Dev/MicYou)（GPL-3.0-or-later with MicYou Plugin Exception）。

**维护原则：能交给 MicYou 的就不自己维护。** 只有两块代码由 liino 自己写：

1. **Flutter UI**（`apps/liino_app`）
2. **蓝牙传输**（MicYou 2.2.0 尚未实现，见第 6 节）

局域网/ USB 连接、mDNS、TCP/UDP 传输、Opus、Jitter Buffer、DSP、AEC、会话状态机、GUI 所需的状态指标，全部复用 `vendor/micyou` 的 Rust 实现。**默认直接 path 依赖 vendor，不复制代码。**

## 1. vendor 布局

MicYou 源码以 **git submodule** 放在 `vendor/`，由主仓库锁定提交：

| 子模块 | 上游 | 用途 | 当前 pin（2026-11-14） |
| :--- | :--- | :--- | :--- |
| `vendor/micyou` | `MicYou-Dev/MicYou`（branch `master`） | Rust 核心、协议、Android/Tauri 前端、插件 | `1ae4318`（v2.2.0） |
| `vendor/micyou-ios` | `MicYou-Dev/MicYou-iOS`（branch `swiftui`） | iOS 平台层与音频生命周期参考 | `b825dba` |

首次检出：

```bash
git submodule update --init --recursive
```

## 2. 直接依赖机制

MicYou 2.2.0 的 Rust 工作区在 `vendor/micyou/tauri-app/`，自带 `[workspace.package]` 与 `[workspace.dependencies]`。

- 根 `Cargo.toml` 用 `exclude = ["vendor"]` 把 vendor 排除出 liino workspace，让 MicYou 的 crate 按自己的 workspace 解析继承字段。
- 需要哪个 crate 就在 `Cargo.toml` 写 path 依赖，例如：

  ```toml
  micyou-core = { path = "../../vendor/micyou/tauri-app/crates/micyou-core", default-features = false }
  ```

- 目前 `packages/liino_api` 已直接依赖 `micyou-core`，并把 `query_network_interfaces()` 暴露为 FRB 的 `networkInterfaces()`。
- `liino-daemon` 仍指向早期复制出来的 `liino-engine`，下一阶段会切换为直接依赖 `micyou-core`，然后删除复制件。

### arboard shim（Android 必需）

`micyou-core` 无条件依赖 `arboard`（仅用于插件剪贴板 API），而 `arboard` 没有 Android 后端、无法编译。liino 不使用插件剪贴板，因此根 `Cargo.toml` 通过 `[patch.crates-io]` 用 `crates/arboard-shim` 替换：API 保留，调用返回 “unavailable”。这样不需要修改 vendor 子模块，也不影响上游同步。

### Android minSdk 26

`micyou-audio` 的 cpal 后端链接 `libaaudio`，NDK 只对 API 26+ 提供该库，因此 `apps/liino_app` 的 `minSdk` 固定为 **26**，`tool/build_android_rust.sh` 使用 `API=26` 的 clang wrapper。

### 许可证

MicYou 是 GPL-3.0-or-later（含插件例外）。直接依赖会让最终二进制按 GPL 分发；`liino-core` / `liino_api` 目前的 Apache-2.0 许可需要在上游代码进入其依赖图后改为 GPL-3.0-or-later，或保持它们不依赖 MicYou（当前 `liino_api` 已依赖，应改许可）。

## 3. 跟进上游

```bash
git submodule update --remote --merge vendor/micyou vendor/micyou-ios
git -C vendor/micyou log --oneline -10
git submodule status
```

不要修改 `vendor/` 内的文件；需要改动时优先通过 feature / patch / 适配层解决，确需上游修改则提交到 MicYou 上游或维护一个最小 fork，并在本文记录。

## 4. 复用映射（MicYou 2.2.0）

| MicYou | liino 用法 | 状态 |
| :--- | :--- | :--- |
| `micyou-protocol` | 直接依赖（替换 `crates/liino-protocol` 复制件） | 待切换 |
| `micyou-infer` | 由 `micyou-core` 间接引入 | 已可用 |
| `micyou-audio`（cpal、DSP、loopback、CoreAudio Tap） | 由 `micyou-core` 间接引入 | 已可用 |
| `micyou-core/src/transport/{tcp,udp,session,opus,jitter_buffer,net_bind}` | 直接依赖 | 待接入 |
| `micyou-core/src/discovery.rs`（mDNS） | 直接依赖，替代自写 UDP presence | 待接入 |
| `micyou-core/src/server/{service,lifecycle,audio_pipeline}` | 直接依赖，作为桌面/移动的会话后端 | 待接入 |
| `micyou-plugin` | 由 `micyou-core` 间接引入，暂不启用 | 已可用 |
| `composeApp/`（Compose 前端） | 只参考业务能力，不复制 UI | 不迁移 |
| `tauri-app/src/` | 参考状态指标（RTT/Jitter/丢包/缓冲水位） | 不迁移 |
| `vendor/micyou-ios` | iOS 平台层参考 | 参考 |

早期为验证而复制出的 `crates/liino-{protocol,infer,audio-core,engine}` 视为**临时件**：随着 `liino_api` / `liino-daemon` 切到直接依赖，逐个删除，避免双份维护。

## 5. 当前自维护范围

- `apps/liino_app`：Flutter UI、页面与状态呈现。
- `apps/liino_app/android`：Kotlin 前台服务、权限、以及未来的蓝牙 RFCOMM 桥。
- `apps/liino_app/macos`：打包与 daemon 进程管理。
- `crates/liino-core`：少量跨端领域类型（RoleMode / TransportType / 能力模型）。
- `crates/liino-daemon`：托盘、IPC、GUI 生命周期（Phase 4）。
- `crates/arboard-shim`：只为 Android 构建存在的 no-op 替身。

## 6. 上游缺口：蓝牙

MicYou 2.2.0 **没有蓝牙传输**，只在测试里确认 `"bluetooth"` 不是合法 `ConnectionMode`：

- `vendor/micyou/tauri-app/crates/micyou-core/src/server/service.rs`：`assert!("bluetooth".parse::<ConnectionMode>().is_err());`
- `composeApp` 只声明了 `BLUETOOTH_*` 权限。

蓝牙必须由 liino 新增平台桥：

| 平台 | 方案 |
| :--- | :--- |
| Android | Kotlin `BluetoothAdapter` 发现 + `BluetoothSocket`（RFCOMM + 固定 UUID），字节流交给 Rust |
| macOS | `IOBluetooth`（`IOBluetoothDeviceInquiry` + `IOBluetoothRFCOMMChannel`） |
| Windows | WinSock `AF_BTH` RFCOMM |
| Linux | BlueZ RFCOMM socket |

## 7. 上游更新检查清单

- [ ] `git submodule update --remote --merge vendor/micyou`
- [ ] 查看 `git -C vendor/micyou log --oneline <old>..HEAD`，重点关注 `transport/`、`server/`、`audio/`、`protocol/`
- [ ] `cargo check`（host + `aarch64-linux-android`）
- [ ] `cargo test -p liino-engine -p liino-audio-core -p liino-protocol`
- [ ] 运行 `apps/liino_app/tool/build_android_rust.sh` 并重建 APK
- [ ] 更新本文件的 pin 与映射状态
