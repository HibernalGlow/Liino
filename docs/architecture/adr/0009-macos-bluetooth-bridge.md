# ADR-0009：macOS 蓝牙通过独立 Swift helper 接入 daemon

- 状态：Accepted
- 日期：2026-11-14（2026-11-15 依据 spike 结果修订）

## 背景

macOS 的 RFCOMM 只有 `IOBluetooth`（Objective-C，自 10.13 起废弃），而桌面引擎是 Rust daemon。候选方案：

1. Rust 直接调 ObjC（`objc` crate + 手写 delegate）：无额外进程，但需要大量 unsafe。
2. **独立 Swift helper 进程**：隔离清楚、直接复用已验证的 Swift 代码，但多一个进程与一次管道拷贝。
3. Objective-C C-ABI 静态库：无额外进程，但 ObjC delegate → C 回调 → Rust 的生命周期管理复杂。

## 决策

采用 **方案 2：独立 Swift helper**。

- 源码：`apps/liino_app/macos/bt_helper/main.swift`；构建：`bt_helper/build.sh`。
- 接口：`liino-bt-helper --address <BT MAC> [--service liino]`，把 RFCOMM 收到的字节写到 stdout，把 stdin 的字节写入 RFCOMM。**不做分帧**，分帧由 daemon 负责（与 TCP/UDP 相同的长度前缀 protobuf）。
- daemon 通过子进程管理：启动、按退出码重启、关闭时终止；helper 的 stderr 进入 daemon 日志。
- 蓝牙 TCC 授权记在宿主 App/daemon 进程；2026-11-15 实测“App bundle 启动子 helper”可以继承授权并成功枚举设备，无需为 helper 单独申请权限。
- 音频帧只在 daemon 与 helper 的管道间流动，不经过 Flutter。

## 依据（spike 结果）

- Android `listenUsingRfcommWithServiceRecord` + macOS SDP 查询 → `openRFCOMMChannelSync` 成功建立通道（channel 7）。
- 1 KB 回显：RTT p50 36.6 ms / p95 96.1 ms；回显吞吐约 11.1 KB/s，足够 Opus 64 kbps。
- 管道带宽远高于 11 KB/s，helper 进程不会成为瓶颈；额外延迟在亚毫秒级。

## 代价

- 多一个需要打包、签名、守护的子进程；崩溃隔离反而更好。
- `IOBluetooth` 已废弃，未来 macOS 可能移除；保留 LAN/USB 回退。
- helper 需要知道设备地址；设备发现仍由 Android 的 NSD / 桌面配对列表提供。

## 备选方案

- C-ABI 静态库：如果后续对延迟/进程数量有硬要求，再切换；接口可保持字节流不变。
- 纯 Rust ObjC：不采用。
