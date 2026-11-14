# ADR-0005：蓝牙主传输采用 Classic RFCOMM

- 状态：Accepted（2026-11-14 确认：Android + macOS 首批，Windows 同为发布目标；macOS RFCOMM 仍需 spike 验证）
- 日期：2026-11-14

## 背景

MicYou 2.2.0 **没有蓝牙传输**：

- `vendor/micyou/tauri-app/crates/micyou-core/src/server/service.rs` 的测试明确断言 `"bluetooth".parse::<ConnectionMode>().is_err()`。
- Android 端只声明了 `BLUETOOTH_*` 权限，没有 RFCOMM 代码。

liino 把蓝牙定为主力传输，因此这部分必须新增。可选技术：

- **Bluetooth Classic RFCOMM**：面向连接、可靠字节流，吞吐通常 1–2 Mbps，足够 Opus 64–128 kbps；延迟高于 Wi-Fi，但可控。
- **BLE GATT**：吞吐与包长受限，不适合连续音频。
- **BLE L2CAP CoC**：需要较新 Android/macOS 支持，跨平台实现复杂。

## 决策（推荐）

1. 采用 **Bluetooth Classic RFCOMM**，把 MicYou 的 protobuf 消息加上长度前缀后作为字节流传输。
2. 连接方向：**手机作为 RFCOMM server**（`listenUsingRfcommWithServiceRecord`，固定 UUID），**桌面作为 client**（按 UUID 查 SDP、取 channel ID 后连接）。数据方向仍是手机 → 桌面；连接发起方与数据方向解耦。这样避免在 macOS 上发布 SDP 记录（`IOBluetoothAddServiceDict` 复杂且已废弃），Android 侧实现也最简单。
3. 帧格式：`u32 length (BE) + protobuf MessageWrapper`；单帧上限与 UDP 路径一致（音频 64 KiB、FEC 1.3 KiB）。RFCOMM 是可靠流，不需要 FEC 的丢包恢复，但保留协议字段以兼容。
4. 传输抽象：在 Kotlin `AudioEngine` 与 Rust `micyou-core` 中各加一个 `BluetoothTransport`，对上暴露与 TCP/UDP 相同的会话接口；连接建立后复用现有会话状态机与统计。
5. 发现：优先使用已配对设备列表 + SDP 查询；未配对时触发系统配对流程。**不做自定义蓝牙广播**。
6. 平台范围：**Android + macOS 首批**；Windows 同为发布目标，需在公开版前完成；Linux 后续。macOS 的 `IOBluetooth` 已废弃且受隐私限制，必须先 spike；若 TCC 阻断，则 macOS 蓝牙降级为“不可用”，LAN/USB 仍可用。

## 平台实现

| 平台 | API | 风险 |
| :--- | :--- | :--- |
| Android | `BluetoothAdapter.listenUsingRfcommWithServiceRecord`（server）+ `BluetoothServerSocket.accept` | Android 12+ 需要 `BLUETOOTH_CONNECT`/`SCAN`，扫描还受位置开关影响 |
| Windows | WinSock `AF_BTH` + `WSALookupService*`（按 UUID 查服务后 `connect`） | 需要蓝牙适配器与配对；文档与示例较少 |
| macOS | `IOBluetoothDevice` + `IOBluetoothRFCOMMChannel.openRFCOMMChannelAsync`（client） | API 自 10.13 起废弃；需要蓝牙 TCC 授权；SDP 查询可用 |
| Linux | BlueZ RFCOMM socket + SDP（client） | 依赖 BlueZ 版本与权限 |

## 必须先验证（spike）

1. Android（server）↔ macOS（client）建立 RFCOMM 通道并稳定传输 20 ms Opus 帧，测量单向延迟、抖动、吞吐。
2. macOS 的 TCC/沙箱是否允许非 App Store 应用打开 RFCOMM 通道；若不允许，macOS 蓝牙降级为“不可用”并在 UI 明示。
3. RFCOMM 流控下的帧粘包/半包处理（长度前缀 + 有界缓冲）。
4. 断线重连、蓝牙关闭/打开、设备休眠后的恢复。
5. 蓝牙与 LAN 同时可用时的优先级与回退策略。

## Spike 记录

- 2026-11-14：macOS 27 上 `IOBluetoothDevice.pairedDevices()` 触发蓝牙 TCC 授权弹窗；授权后成功枚举 10 台已配对设备（含 Xiaomi 15）。
- 2026-11-14：SDP 查询成功，可读取服务名与 RFCOMM channel ID（Xiaomi 15 的 Handsfree Gateway = 1、SMS/MMS = 26 等），证明 client 侧按 UUID 找 channel 的路径可用。
- 2026-11-15：端到端打通。Android `listenUsingRfcommWithServiceRecord("liino", UUID)` 发布服务；macOS SDP 查到 `liino` channel 7，`openRFCOMMChannelSync` 成功，收到 `LIINO-BT-READY`，发送 `hello` 收到 `echo:hello`。
- 2026-11-15 实测（Xiaomi 15 ↔ macOS，RFCOMM，1 KB 回显）：RTT min 26.0 ms / p50 36.6 ms / p95 96.1 ms；吞吐约 11.1 KB/s（单向 payload，回显双向约 190 kbps）。结论：足够 Opus 64 kbps + 20 ms 帧（约 8 KB/s），但 p95 抖动偏高，必须依赖 Jitter Buffer；最终帧格式尚未接入。

## 代价

- 三端各写一套平台桥，无法复用 MicYou 现成代码。
- 蓝牙带宽与延迟不如 Wi-Fi，音质参数需要单独调优。
- macOS 可能无法支持，产品需要接受平台差异。

## 备选方案

- BLE L2CAP CoC：推迟评估。
- 仅 Android↔Windows 支持蓝牙，macOS 走 LAN/USB：可作为降级方案。
