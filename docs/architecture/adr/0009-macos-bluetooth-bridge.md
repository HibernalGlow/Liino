# ADR-0009：macOS 蓝牙通过 Objective-C C-ABI shim 接入 daemon

- 状态：Proposed（实现前需验证 TCC 归属）
- 日期：2026-11-14

## 背景

macOS 的 RFCOMM 只有 `IOBluetooth`（Objective-C，自 10.13 起废弃），而 liino 的桌面引擎是 Rust daemon。需要选一种跨语言边界：

1. **Rust 直接调 ObjC**（`objc` crate + 手写 delegate 类）：无额外进程，但需要大量 unsafe 与 runtime 类构造。
2. **独立 Swift/ObjC helper 进程**（stdio/JSON 或 XPC）：隔离清楚，但多一个进程、多一层音频帧拷贝与生命周期管理。
3. **Objective-C C-ABI shim 静态库**：用少量 `.m` 实现 `IOBluetooth` delegate，暴露 `liino_bt_*` C 函数，由 `build.rs`/`cc` 编译进 daemon。

## 决策（推荐）

采用 **方案 3**：

- `crates/liino-platform/macos/liino_bt.m` 暴露 C ABI：
  - `liino_bt_list_paired()` → JSON 数组（名称、地址、是否已连接）。
  - `liino_bt_find_channel(address, uuid)` → RFCOMM channel ID 或错误。
  - `liino_bt_open(address, uuid, on_data, on_close, ctx)` → 异步打开通道，数据回调直接给 Rust。
  - `liino_bt_write(handle, bytes, len)` / `liino_bt_close(handle)`。
- Rust 侧用 `extern "C"` 绑定 + `Arc`/回调，不做 ObjC runtime 操作。
- 音频帧不经过进程边界；回调直接进入 `micyou-core` 的会话缓冲。
- 该 shim 只在 `cfg(target_os = "macos")` 编译；Windows 用 Rust WinSock，Android 用 Kotlin，互不影响。

## 代价

- Rust 侧仍需 `unsafe extern` 与生命周期管理；shim 崩溃会影响 daemon。
- `IOBluetooth` 已废弃，未来 macOS 可能移除；需要保留 LAN/USB 回退。
- **TCC 归属未验证**：蓝牙授权可能记在 GUI 应用而不是 daemon 进程；若 daemon 无法获得授权，需要把 shim 放进一个带 `Info.plist` 的 helper bundle，或改由 GUI 进程代理蓝牙（与 ADR-0004 冲突）。这是实现前的阻塞项。

## 备选方案

- helper 进程：TCC 归属更容易控制（独立 bundle），但音频流多一次拷贝；作为 TCC 验证失败时的退路。
- 纯 Rust ObjC：代码量最大、unsafe 最多，暂不采用。

## 验收

- daemon 能在获得蓝牙授权后枚举设备、按 UUID 找到 channel、建立 RFCOMM 连接并收发字节。
- 关闭 GUI 后蓝牙链路继续工作（验证 daemon 持有 TCC 身份）。
