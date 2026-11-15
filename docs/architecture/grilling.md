# 决策 Grill：已确认的细节

2026-11-14 确认完毕。实现中若前提不成立，先改 ADR，再改代码。

## 1. 已确认决策

| # | 决策 | 结论 | ADR |
| :--- | :--- | :--- | :--- |
| Q1 | 移动端引擎 | 沿用 MicYou 原生 Kotlin/Swift；Flutter 只发控制、收状态 | 0003 |
| Q2 | 蓝牙首批平台 | **Android + macOS 首批**；Windows 同为发布目标；Linux 后续 | 0005 |
| Q2b | 蓝牙抽象层 | 不用 Qt / Web Bluetooth；Android 用 Kotlin 原生；macOS/Windows/Linux 首选 `webbluetooth` 0.0.4（macOS 2026-11-15 真机 spike 通过，helper 降为回退；见 0005 备选 / 0009 复评更新） | 0005 |
| Q3 | v1 会话方向 | 手机 → 桌面（沿用 MicYou 语义） | 0003 |
| Q4 | 与 MicYou 互通 | 同端口 9123/9124、同 mDNS、同 protobuf | 0006 |
| Q5 | 许可证 | **整体 GPL-3.0-or-later**；保留 LocalSend 派生文件的 Apache-2.0 头 | 0007 |
| Q6 | 局域网安全 | **v1 不鉴权**，仅限可信 LAN；蓝牙依赖 OS 配对 | 0008 |
| Q7 | USB | 沿用 MicYou 的 ADB 方案（桌面需 adb，手机开 USB 调试） | 0006 |
| Q8 | 桌面平台 | **macOS 与 Windows 都要**；macOS 先行开发，Windows 发布前完成同等验证 | 0004 |
| Q9 | 旧复制件 | 保留到 daemon/移动端切换完成再删 | 0001 |
| Q10 | Flutter 状态 | Refena + 事件订阅；发现列表 1–2 s 轮询兜底 | — |
| Q11 | vendor 更新 | 跟 `master`，每次升级跑回归清单 | 0001 |
| Q12 | 设备命名 | 主机名/机型 + 平台，可在设置中改名并持久化 | — |
| Q13 | 自维护范围 | 仅 Flutter UI + 蓝牙 + 薄桥 | 0001 |
| Q14 | Rust 工具链 | 固定 1.97.1；host 与 Android 均已验证 | — |

## 2. 仍需完成的技术 Spike

这些不影响已定方向，但决定实现细节与降级路径：

1. **Kotlin 复用边界**：能否用 Gradle `sourceSets` 直接编译 MicYou 的 `DeviceDiscovery.kt` / `AudioEngine.kt`，而不引入 Compose/ViewModel；若不能，明确最小重写范围。
2. **macOS RFCOMM**：`IOBluetoothRFCOMMChannel` 在当前 macOS 27 + TCC 下能否打开通道。2026-11-14 实测：`IOBluetoothDevice.pairedDevices()` 会触发系统“允许使用蓝牙”授权弹窗，未授权时调用阻塞；需用户点“允许”后再验证通道打开。若最终被阻断，macOS 蓝牙 UI 明示不可用，LAN/USB 不受影响（与 Q2 联动）。
3. **Windows RFCOMM**：`AF_BTH` + `WSASetService`/`WSALookupService*` 的服务注册与发现；需在 Windows 11 实机验证。2026-11-15 复评：`webbluetooth` 0.0.4 已实现 Winsock 客户端（含按 UUID 连接）与服务端，可作首选候选或 MIT 参考（见 ADR-0005 备选）；本拓扑桌面只做 client，无需 `WSASetService`。
4. **RFCOMM 吞吐/延迟**：Android ↔ macOS / Windows，20 ms Opus 帧；测单向延迟、抖动、断线重连。
5. **daemon 集成 `micyou-core`**：`ServerState` 需要 `SharedEvents` / `SharedHost`；确认托盘、单实例、退出清理的接入点。
6. **IPC 事件流**：现有 JSON-line 增加订阅与背压；16 KiB 帧上限、慢客户端丢弃策略。
7. **Android NSD/mDNS 权限**：`NsdManager` 无需 MulticastLock；确认 macOS 本地网络权限弹窗流程。

## 3. 生效规则

- 实现中若 ADR 前提不成立（例如 macOS 无法 RFCOMM），先改 ADR，再改代码。
- 新增跨模块选择（端口、协议、存储、线程模型）必须新增 ADR，不能只写在提交信息里。
- 任何“临时复制”的代码必须标注来源与删除条件。
