# MicYou 现有代码审计与迁移清单（Current Code Audit）

审计目标仓库：[MicYou-Dev/MicYou](https://github.com/MicYou-Dev/MicYou)（版本 v2.1.1，许可证 GPL-3.0-or-later with MicYou Plugin Exception）。

## 1. 现有 Rust Workspace 资产评估

MicYou 在近期的重构中（如 `#352` 抽离 Tauri 无关的 `micyou-core`、`PureVox6/AEC7` 纯 Rust 推理 VM）已经具备极高的复用价值：

| 原 Crate / 模块 | 核心职责 | 复用评估 | 迁移处理方式 |
| :--- | :--- | :--- | :--- |
| `crates/micyou-protocol` | `proto/network.proto`（`prost` 编解码：音频包、FEC、Ping/Pong、Stats、PluginMessage） | **直接复用** | 迁移为 `liino-protocol`，保持线协议向后兼容并扩展双向角色协商字段 |
| `crates/micyou-infer` | 纯 Rust 推理 VM（`PureVox6` 降噪 / `AEC7` 回声消除，零 C/ONNX Runtime 依赖） | **直接复用** | 迁移为 `liino-audio-core` 可选 feature，按需加载以控制内存 |
| `crates/micyou-audio` | `cpal` 音频引擎、DSP 管线（`nnnoiseless`、`rustfft`、`rubato` 重采样、`ringbuf`、`aec.rs`、macOS CoreAudio Tap、Windows WASAPI Loopback） | **高度复用** | 迁移为 `liino-audio-core`，将发送端采集与接收端播放统一为双向管线 |
| `crates/micyou-plugin` | 双运行时插件系统（`libloading` Native + `wasmi` WASM）与 DSP 节点扩展 | **后期复用** | 保持独立 Crate，Phase 4/5 按需接入，默认不加载运行时 |
| `crates/micyou-core` | 服务端生命周期、`transport/`（TCP/UDP/JitterBuffer/Opus/Web/Session）、`discovery.rs`（mDNS）、`platform/`（VB-CABLE/BlackHole/PipeWire/ADB/usbmux） | **拆分重构** | 剥离 `headless-host` 桌面 UI 假设（`arboard`、`open`、`notify-rust`、`global-hotkey`），拆分为 `liino-engine` 与 `liino-platform` |
| `crates/micyou-cli` & `micyou-tui` | 无头 CLI 与终端 TUI | **参考借鉴** | 参考其无头启动模式，用于设计 `liino-daemon` 的独立运行模式 |

## 2. 蓝牙实现与多平台差异调查

- **MicYou 现状**：经源码检索，`micyou-core/src/server/service.rs` 中尚存在 `assert!("bluetooth".parse::<ConnectionMode>().is_err())`，说明当前 2.x Rust 核心**尚未实现蓝牙传输模式**；仅在 `composeApp/src/main/AndroidManifest.xml` 中保留了 `BLUETOOTH`、`BLUETOOTH_ADMIN`、`BLUETOOTH_CONNECT`、`BLUETOOTH_SCAN` 权限声明。
- **liino 迁移策略**：
  - 将传输抽象为统一的 `TransportType`（`LanWifi`、`Usb`、`BluetoothRfcomm`）。
  - **Android**：通过原生 Kotlin Platform Channel / JNI 封装 `BluetoothSocket` (RFCOMM) 并向 Rust 暴露字节流桥接。
  - **Windows / Linux / macOS**：分别适配 WinSock RFCOMM (`AF_BTH`)、BlueZ RFCOMM Socket 与 macOS `IOBluetoothRFCOMMChannel`，不假设跨平台蓝牙 API 一致。

## 3. 需要重写的模块（不直接复用）

1. **UI 与状态管理**：`composeApp/`（Android Jetpack Compose）与 `tauri-app/src/`（Vue 3 + TypeScript）全部由统一的 Flutter + Material 3 Expressive UI 替换，但需完整对齐其核心业务能力与状态指标（RTT、Jitter、丢包率、缓冲区水位、插件联动）。
2. **桌面端宿主生命周期**：原 `src-tauri/` 依赖 Tauri WebView 进程模型，需重写为独立 `liino-daemon` + IPC（Windows Named Pipe / Unix Domain Socket）+ Flutter GUI 进程管理器，以实现关闭窗口后彻底释放 Flutter 内存。
3. **Android 采集与前台服务**：Phase 3 阶段优先保留/适配 MicYou 原有 Android 前台服务（`ForegroundService`）与麦克风权限管理，逐步将网络/Opus/DSP 下沉至 Rust Core，避免一次性重写所有原生生命周期引发回归。
