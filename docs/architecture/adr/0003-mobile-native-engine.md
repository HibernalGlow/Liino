# ADR-0003：移动端沿用 MicYou 原生引擎

- 状态：Accepted（依据“除蓝牙与 Flutter UI 外交给 MicYou”的产品约束）
- 日期：2026-11-14

## 背景

MicYou 的移动端不是 Rust：

- Android：`composeApp/.../audio/AudioEngine.kt` 使用 `AudioRecord`、Kotlin Opus（concentus）、`DatagramSocket`，并自带录音所有权与前台服务逻辑。
- iOS：`vendor/micyou-ios` 是 Swift 实现。

liino 的移动端要把 Compose/SwiftUI 换成 Flutter UI。若把 MicYou 的采集/编码/传输搬到 Rust，会重写一套已经稳定的实现，与“维护量最小”冲突；若保留原生引擎，则移动端存在两套传输实现（Kotlin/Swift），需要与桌面 Rust 协议保持一致。

## 决策（推荐）

1. **移动端音频与传输仍由 MicYou 原生引擎负责**：采集、Opus、UDP/TCP、会话状态、前台服务都在 Kotlin/Swift。
2. Flutter 只通过 MethodChannel 下发控制（连接/断开/角色/参数）并接收节流后的状态事件；**PCM 不穿越 Flutter 通道**。
3. 移动端不通过 FRB 跑音频引擎；`liino_api` 在 Android 上只用于非实时能力（如网络接口、版本信息）或直接移除。
4. 蓝牙作为“新增传输”分别接入两端：Android 在 Kotlin 引擎里加 RFCOMM；桌面在 Rust `micyou-core` 里加 RFCOMM；共用同一套帧格式（见 ADR-0005）。
5. 桌面端保留 Rust 引擎（daemon 内嵌 `micyou-core`，见 ADR-0004）。

## 代价

- 没有“单一引擎代码库”；Android/iOS/桌面三端需要各自维护蓝牙与传输适配。
- Flutter 与原生之间需要定义稳定的控制/事件协议，并处理生命周期（后台、断连、权限）。
- 未来若要统一到 Rust，需要一次大迁移（可通过协议层先统一来降低风险）。

## 备选方案

- **全 Rust（FRB）**：统一语言与内存模型，但要重写 Kotlin 的录音所有权、Opus、前台服务与 iOS 音频会话，工期与回归风险最大；否决。
- **仅桌面复用 MicYou、移动端重写**：不满足维护量约束。

## 需要先验证

- 能否在不引入 Compose 的前提下，把 `DeviceDiscovery.kt` / `AudioEngine.kt` 作为 Gradle `sourceSets` 直接编译进 liino 的 Android 工程（而不是复制代码）。若依赖 Compose/ViewModel 过深，则退化为“只复用协议与流程，代码在 liino 内重写薄层”。
- MicYou Android 的 `AudioEngine` 是否可剥离 `Service`/通知依赖，仅保留引擎。
