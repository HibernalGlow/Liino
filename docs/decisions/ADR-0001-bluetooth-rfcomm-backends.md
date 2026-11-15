# ADR-0001: Bluetooth Classic RFCOMM 跨平台原生 Rust 路线（更新：`webbluetooth 0.0.4`）

- **状态**: Accepted（基于 `webbluetooth 0.0.4` 实查结论更新）
- **日期**: 2026-11-15

## 背景与约束

`liino` 需要支持通过 Bluetooth Classic RFCOMM 在 Android、Windows、macOS（第一优先级）与 Linux（第二优先级）之间传输音频流。约束条件：
- 不引入额外的第三方运行时进程（禁止 Python / Go / Qt / .NET / Node）。
- 由 Rust Core 直接持有蓝牙传输字节流与协议状态机，不经 Dart 中转高频音频数据。

## 调研结论与选型

1. **首选实验基座：`webbluetooth`（`0.0.4`，MIT，`features = ["rfcomm"]`）**
   - 纯 Rust 原生调用各平台系统接口（Android / Windows / Linux 支持 RFCOMM Client + Server；macOS 基于 `IOBluetooth` 支持 RFCOMM Client），无需额外运行时或独立系统服务。
   - **已知成熟度边界**：当前仅 3 Stars / 5 Commits，0.0.4 仅在 Mac ↔ Ubuntu 验证过 RFCOMM；Android 与 Windows 尚未完成真实硬件验证，需作为 PoC 重点验证对象。
2. **macOS SDP Channel 解析补齐（`bluetooth_rfcomm` C ABI / `IOBluetooth`）**
   - `webbluetooth` 0.0.4 在 macOS 端需要显式 RFCOMM Channel 号，而 Android 服务端通过 SDP 发布的 Channel 可能是动态分配的。
   - 复用 `Bud-ro/dart-bluetooth`（`bluetooth_rfcomm`）中已处理的 Objective-C + `IOBluetooth` C ABI（如 `btc_sdp_channel(address, uuid)`）或等价轻量 `IOBluetooth` FFI 查询目标设备的动态 RFCOMM Channel，再交给 `webbluetooth` 建立连接。
   - 需在 macOS 启用 `com.apple.security.device.bluetooth` entitlement，并确保 `IOBluetooth` 回调运行在主线程 RunLoop（设备需先在系统设置完成配对）。
3. **备选对比**：`flutter_classic_bluetooth`（MIT 1.7.4）虽全平台支持但需经 Dart MethodChannel/EventChannel 中转字节流，不符合 Rust Core 直管传输的要求，仅作兜底备选。

## 角色解耦的连接拓扑（发起方 != 音频发送方）

RFCOMM 是全双工双向字节流，因此将“蓝牙连接发起方”与“音频发送方”解耦：

| 对端组合 | RFCOMM Server（监听方） | RFCOMM Client（发起方） | 音频流向 |
| :--- | :--- | :--- | :--- |
| **Android ↔ Windows** | Windows：`listen_rfcomm(channel)` | Android：`open_rfcomm_service(uuid)` | Android → Windows（或双向） |
| **Android ↔ macOS** | Android：`listen_rfcomm_service(name, uuid)` | macOS：`btc_sdp_channel` 查通道后 `open_rfcomm_channel(addr, ch)` | Android → macOS（或双向） |

## 后续 PoC 验证项

1. 在真机上验证 Android ↔ macOS（`IOBluetooth` RunLoop + SDP Channel 解析）与 Android ↔ Windows 的 RFCOMM 建链。
2. 验证长时间传输 Opus 音频帧时的断线重连恢复与有界缓冲表现。
