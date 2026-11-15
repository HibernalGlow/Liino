# ADR-0005：蓝牙主传输采用 Classic RFCOMM

- 状态：Accepted（2026-11-14 确认：Android + macOS 首批，Windows 同为发布目标；2026-11-15 Android↔macOS 端到端 spike 通过；webbluetooth 0.0.4 复评见「备选方案」）
- 日期：2026-11-14

## 背景

MicYou 2.2.0 **没有蓝牙传输**：

- `vendor/micyou/tauri-app/crates/micyou-core/src/server/service.rs` 的测试明确断言 `"bluetooth".parse::<ConnectionMode>().is_err()`。
- Android 端只声明了 `BLUETOOTH_*` 权限，没有 RFCOMM 代码。

liino 把蓝牙定为主力传输，因此这部分必须新增。可选技术：

- **Bluetooth Classic RFCOMM**：面向连接、可靠字节流，吞吐通常 1–2 Mbps，足够 Opus 64–128 kbps；延迟高于 Wi-Fi，但可控。
- **BLE GATT**：吞吐与包长受限，不适合连续音频。
- **BLE L2CAP CoC**：需要较新 Android/macOS 支持，跨平台实现复杂。

## 决策（2026-11-15 确认：继续各平台原生实现）

1. 采用 **Bluetooth Classic RFCOMM**，把 MicYou 的 protobuf 消息加上长度前缀后作为字节流传输。
2. 连接方向：**手机作为 RFCOMM server**（`listenUsingRfcommWithServiceRecord`，固定 UUID），**桌面作为 client**（按 UUID 查 SDP、取 channel ID 后连接）。数据方向仍是手机 → 桌面；连接发起方与数据方向解耦。这样避免在 macOS 上发布 SDP 记录（`IOBluetoothAddServiceDict` 复杂且已废弃），Android 侧实现也最简单。
3. 帧格式：`u32 length (BE) + protobuf MessageWrapper`；单帧上限与 UDP 路径一致（音频 64 KiB、FEC 1.3 KiB）。RFCOMM 是可靠流，不需要 FEC 的丢包恢复，但保留协议字段以兼容。
4. 传输抽象：在 Kotlin `AudioEngine` 与 Rust `micyou-core` 中各加一个 `BluetoothTransport`，对上暴露与 TCP/UDP 相同的会话接口；连接建立后复用现有会话状态机与统计。
5. 发现：优先使用已配对设备列表 + SDP 查询；未配对时触发系统配对流程。**不做自定义蓝牙广播**。
6. 平台范围：**Android + macOS 首批**；Windows 同为发布目标，需在公开版前完成；Linux 后续。macOS 的 `IOBluetooth` 已废弃且受隐私限制，必须先 spike；若 TCC 阻断，则 macOS 蓝牙降级为“不可用”，LAN/USB 仍可用。

## 平台实现（最终方案）

| 平台 | API | 风险 |
| :--- | :--- | :--- |
| Android | `BluetoothAdapter.listenUsingRfcommWithServiceRecord`（server）+ `BluetoothServerSocket.accept` | Android 12+ 需要 `BLUETOOTH_CONNECT`/`SCAN`，扫描还受位置开关影响 |
| Windows | WinSock `AF_BTH` + `WSALookupService*`（按 UUID 查服务后 `connect`） | 需要蓝牙适配器与配对；文档与示例较少 |
| macOS | `IOBluetoothDevice` + `IOBluetoothRFCOMMChannel.openRFCOMMChannelAsync`（client） | API 自 10.13 起废弃；需要蓝牙 TCC 授权；SDP 查询可用 |
| Linux | BlueZ RFCOMM socket + SDP（client） | 依赖 BlueZ 版本与权限 |

> 2026-11-15 复评：Windows/Linux 行优先评估 `webbluetooth` crate（0.0.4 已有两平台原生实现，见「备选方案」）；Android/macOS 行维持原生实现不变。

## 必须先验证（spike）

1. Android（server）↔ macOS（client）建立 RFCOMM 通道并稳定传输 20 ms Opus 帧，测量单向延迟、抖动、吞吐。
2. macOS 的 TCC/沙箱是否允许非 App Store 应用打开 RFCOMM 通道；若不允许，macOS 蓝牙降级为“不可用”并在 UI 明示。
3. RFCOMM 流控下的帧粘包/半包处理（长度前缀 + 有界缓冲）。
4. 断线重连、蓝牙关闭/打开、设备休眠后的恢复。
5. 蓝牙与 LAN 同时可用时的优先级与回退策略。

## Spike 记录

> 现状口径（2026-11-15）：以下均为 demo 级 spike（验证路径可行 + 量延迟/吞吐），**生产 BluetoothTransport（分帧 + 会话 + 接入引擎）尚未在任何平台实现**——Android `BluetoothRfcommServer.kt` 仍是 line echo（自陈「the audio transport is wired later」），daemon `bluetooth.rs` 只 drain 字节、`write` 尚 `dead_code`，`BluetoothTransport` 仅存在于本 ADR 决策 4 的计划中。因此平台选型是「生产传输建在什么底座上」的前瞻决定，不是「保护现成实现」。

- 2026-11-14：macOS 27 上 `IOBluetoothDevice.pairedDevices()` 触发蓝牙 TCC 授权弹窗；授权后成功枚举 10 台已配对设备（含 Xiaomi 15）。
- 2026-11-14：SDP 查询成功，可读取服务名与 RFCOMM channel ID（Xiaomi 15 的 Handsfree Gateway = 1、SMS/MMS = 26 等），证明 client 侧按 UUID 找 channel 的路径可用。
- 2026-11-15：端到端打通。Android `listenUsingRfcommWithServiceRecord("liino", UUID)` 发布服务；macOS SDP 查到 `liino` channel 7，`openRFCOMMChannelSync` 成功，收到 `LIINO-BT-READY`，发送 `hello` 收到 `echo:hello`。
- 2026-11-15 实测（Xiaomi 15 ↔ macOS，RFCOMM，1 KB 回显）：RTT min 26.0 ms / p50 36.6 ms / p95 96.1 ms；吞吐约 11.1 KB/s（单向 payload，回显双向约 190 kbps）。结论：足够 Opus 64 kbps + 20 ms 帧（约 8 KB/s），但 p95 抖动偏高，必须依赖 Jitter Buffer；最终帧格式尚未接入。
- 2026-11-15（webbluetooth 0.0.4 复评）：通读 facade/apple/core/windows/android/linux 六 crate 源码；本机 spike（`=0.0.4` + `rfcomm`，Rust 1.97.1）5.31 s 构建通过，产物链接 `IOBluetooth.framework`，依赖闭包 10 crate、无异步运行时。确认 macOS RFCOMM 客户端为真实现（mock 仅 `#[cfg(test)]`）。结论见「备选方案」webbluetooth 条。
- 2026-11-15（webbluetooth macOS 真机 spike，Xiaomi 15 ↔ macOS）：生产形态 spike（主线程 CFRunLoop + 工作线程 async + 手写 SDP-by-UUID objc FFI + webbluetooth open）跑通。SDP 按 UUID 命中 channel 7；**bundle 未加蓝牙 entitlement、非沙箱、ad-hoc 签名，靠 TCC 即打开**（webbluetooth 文档「必须 entitlement」在本机被证伪）。两次 RTT p50 36.1 / 43.9 ms（与 helper 36.6 ms 持平），p95 130–140 ms。串行 1 KiB echo ≈ 7.4 KiB/s（61 kbps）、pipelined ≈ 6.5–8.9 KiB/s——**RTT 受限的回显吞吐，非生产单向流**，生产单向 Opus 吞吐列为必验项。判定：macOS 转 webbluetooth in-daemon，helper 降为回退（详见 ADR-0009 复评更新）。

## 代价

- 三端各写一套平台桥，无法复用 MicYou 现成代码。
- 蓝牙带宽与延迟不如 Wi-Fi，音质参数需要单独调优。
- macOS 可能无法支持，产品需要接受平台差异。

## 备选方案（已评估）

- **浏览器 Web Bluetooth**：只支持 BLE GATT，访问不到 Classic 蓝牙的 RFCOMM/SPP；GATT 通知的吞吐与连接间隔延迟不适合连续音频，且 Safari/Firefox 不支持。**否决**。浏览器场景应走 MicYou 已有的 HTTP/WebSocket web 模式。
- **Rust `webbluetooth` crate**（2026-11-15 复评，0.0.4）：不是纯浏览器绑定；各平台原生后端提供 Web Bluetooth 形状的 API。0.0.2 时的否决理由（「rfcomm 只在 Linux 与 Android 实现」）**已不成立**：0.0.4 的 `rfcomm` feature 覆盖四平台——macOS 客户端（IOBluetooth `openRFCOMMChannelAsync`、运行时合成 delegate、每通道 pump 线程）、Windows 客户端+服务端（Winsock `AF_BTH`，客户端可按服务 UUID 直连）、Android 客户端+服务端（JNI）、Linux 客户端+服务端+SDP。仍存在的缺口：macOS 仅客户端、无 SDP 查询封装（`query_sdp` 仅 Linux）、必须显式传 channel 号；Windows `listen` 不发布 SDP 记录（本 ADR 拓扑桌面只做 client，不受影响）。成熟度：3★/0 fork/5 commits（2026-09-21 建仓），真机记录仅 Mac↔Ubuntu 5/5，Android/Windows RFCOMM 未经真机验证。**分平台结论**（生产传输未建，见 Spike 记录现状口径）：Android 用 Kotlin 原生——demo 是 line echo，生产需重写成帧传输接入 AudioEngine；选 Kotlin 是因引擎在 Kotlin、集成形状最简（ADR-0003），webbluetooth-android 会让 Kotlin 引擎绕道 Rust/JNI 再回 BluetoothSocket，无谓；macOS 真机 spike 通过、转为首选（见 ADR-0009 复评更新），helper 降为回退；**Windows/Linux 实现转为首选候选**——Windows client-by-UUID 与本 ADR 原 WinSock 计划一致，可直接依赖或按 MIT 作参考实现；Linux 角色与 SDP 齐全。重评触发：出现真机记录/社区采纳，或 Windows/Linux 传输开工。
- **Qt Bluetooth FFI**：Qt 6 的 Classic Bluetooth（`QBluetoothSocket` RFCOMM）在 Android/Linux/macOS/Windows 均有后端，技术上可用。但需要把 QtCore/QtBluetooth（macOS 还需 QGuiApplication 事件循环）链入 Rust daemon，增加数十 MB 运行时、LGPLv3 合规与 C++ 构建链；macOS 后端本质上仍依赖 IOBluetooth（同样面临废弃风险）。**否决**，收益不抵成本。
- BLE L2CAP CoC：推迟评估。
- 仅 Android↔Windows 支持蓝牙，macOS 走 LAN/USB：可作为降级方案。
