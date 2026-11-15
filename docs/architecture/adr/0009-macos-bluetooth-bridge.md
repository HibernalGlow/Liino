# ADR-0009：macOS 蓝牙通过独立 Swift helper 接入 daemon

- 状态：Accepted（2026-11-15 webbluetooth macOS 真机 spike 通过，生产方向复评为 webbluetooth in-daemon、helper 降为回退；见「复评更新」，保留两项生产门槛）
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

## 复评更新（2026-11-15，webbluetooth macOS 真机 spike）

对备选方案中的 `webbluetooth` 0.0.4 做了生产形态 spike（主线程 `CFRunLoopRun` + 工作线程 async + 手写 SDP-by-UUID objc FFI + webbluetooth `open_rfcomm_channel`），对着真机 Xiaomi 15（`F0:2C:7B:FB:CA:9F`，Android demo 在 channel 7 监听）跑通：

- **SDP-by-UUID FFI 成功**：`performSDPQuery` + `getServiceRecordForUUID` + `getRFCOMMChannelID`，约 60 行 unsafe，按 UUID 命中 channel 7。理由②的 unsafe 成本被量化为小而有界。
- **webbluetooth open 成功，且无需蓝牙 entitlement**：spike bundle 非沙箱、ad-hoc 签名、**未加** `com.apple.security.device.bluetooth`，靠 TCC 授权即打开。webbluetooth 文档「必须 entitlement」在 macOS 27 本机**被证伪**（与 helper 经验一致）。
- **主线程 RunLoop 模式可行**：理由①的入口重构有可跑通的范式（spike 即此模式）；仍是跨传输改动，但有界。
- **延迟与 helper 持平**：两次 RTT p50 36.1 / 43.9 ms（helper 那次 36.6 ms），p95 130–140 ms，需 Jitter Buffer（与 ADR-0005 一致）。
- **吞吐口径**：串行 1 KiB echo ≈ 7.4 KiB/s（61 kbps），pipelined ≈ 6.5–8.9 KiB/s。**这是 RTT 受限的回显吞吐，不是生产单向流吞吐**——生产音频是手机→桌面单向连续发送，不按帧等回显，且 RFCOMM 空口 1–2 Mbps 远高于 64 kbps。echo demo 无法判定生产单向吞吐，**列为生产前必验项**（需两端先接分帧）。

**判定：macOS 生产传输转向 webbluetooth in-daemon（方案 1 的成熟 crate 形态），helper 降为回退。** 依据：viability 已真机证明、三条顾虑均被解决/量化、entitlement 证伪、延迟持平，且与「Rust 核心自包含、daemon/UI 分离」方向一致（ADR-0004）。成熟度风险（0.0.4 / 5 commits / 0 fork）作为预发布个人项目接受，以传输契约（ADR-0005 决策 4）保证可换回 helper（UI/协议零改动）。

**保留门槛**（任一不过则回退 helper）：① 生产单向 Opus 流吞吐/丢包实测（echo 不算数）；② daemon 主线程 RunLoop 重构对 LAN/USB 传输的回归。

## 备选方案

- C-ABI 静态库：如果后续对延迟/进程数量有硬要求，再切换；接口可保持字节流不变。
- 纯 Rust ObjC：不采用。
- Rust `webbluetooth` crate（2026-11-15 复评，0.0.4）：`webbluetooth-apple` 的 RFCOMM 客户端是真 IOBluetooth 实现（pump 线程 + 运行时合成 delegate + MTU 分片 + entitlement 错误提示），本机构建通过（见 ADR-0005 spike 记录）。**原评估（spike 前）暂不采用**，三条理由：① IOBluetooth 回调走主线程 RunLoop，daemon 是 `#[tokio::main]`，替换需把主线程让给 `CFRunLoopRun`、tokio 移到工作线程，入口重构波及所有传输；② macOS 侧无 SDP 查询，而 Android 的 RFCOMM channel 动态分配（spike 实测 channel 7），需自写 `performSDPQuery` objc FFI——正是本 ADR 方案 2 要避开的 unsafe；③ 3★/5 commits/0 fork、无 Android 真机记录，上音频主路径有依赖风险。**口径校准**：现有 helper 与 daemon 蓝牙链路都是 demo 级，生产传输两条路都要从头建——helper 路径剩余 BT 工作（守护/重启/打包签名）更少，SDP 与 RunLoop 已在 helper 内解决，无跨传输入口重构、无新依赖；webbluetooth 路径反而要自补 SDP FFI + 重构 daemon 主线程。故首发选 helper 的依据是「剩余工作更少、风险更低」，不是「保护现成实现」；crate 成熟后可按传输契约换入（UI/协议零改动）。**重评触发**：crate 出现真机记录/社区采纳；或 Windows/Linux 传输开工（同 crate 覆盖两平台，统一依赖有价值）；或 helper 进程成为真实的打包/签名/延迟负担。**→ 2026-11-15 真机 spike 后改判为首选，三条顾虑的处置与保留门槛见「复评更新」。**
