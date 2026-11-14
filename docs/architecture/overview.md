# liino 总体架构设计（Architecture Overview）

## 1. 产品定位与统一模型

`liino` 是跨平台、双向能力、低延迟的音频通信应用，将传统“手机发送端 + 桌面接收端”双应用合并为统一产品：

- **统一运行模式**：
  ```rust
  pub enum RoleMode {
      Auto,
      Sender,
      Receiver,
  }
  ```
- **能力驱动而非平台硬编码**：运行时通过 `DeviceCapabilities` 检测真实系统能力（`can_capture_audio`、`can_play_audio`、`can_virtual_microphone`、`supported_transports`），`Auto` 模式下默认 Android / iOS 为 `Sender`，Windows / macOS / Linux 为 `Receiver`；手动切换仅开放当前设备真实支持的能力。

### UI 组件库与布局借鉴策略（不重复造轮子）

- **MD3 Expressive 组件库**：直接使用 [`material_3_expressive`](https://pub.dev/packages/material_3_expressive)（`^1.2.1`，MIT）与 [`material_ui`](https://pub.dev/packages/material_ui)（`^1.11.0`）提供的 `M3EMaterialApp`、`M3EThemeData`、`M3ENavigationRail`、`M3ENavigationBar`、`M3ESegmentedButton`、`M3EButton`、`M3ECard`、`M3EList`、`M3EProgressIndicator`（含 wavy 波形进度条）等组件，禁止手搓重复的圆角令牌或基础控件。
- **工程布局与交互参考**：
  - 借鉴本地 `Rossi` 项目的 `SettingPageShell`（`M3EAppBar.sliver(largeFlexible)` + `scroll_spy` 吸顶目录）与双栏设置布局。
  - 借鉴 [FlClash](https://github.com/chen08209/FlClash) 的桌面侧栏 / 悬浮 Dock 适配与 `CoreController` 状态防抖（600ms connecting 最小展示窗口）设计。

## 2. 分层架构与通信边界

```text
+-------------------------------------------------------------------+
|                        Flutter UI (Dart)                          |
|   Material 3 Expressive Design System · 页面导航 · 状态呈现         |
+---------------------------------+---------------------------------+
                                  |
             +--------------------+--------------------+
             | 移动端（同进程）                          | 桌面端（跨进程）
             v                                         v
   +-------------------+                     +-------------------+
   | FRB (Dart <-> Rust)|                    | CoreGateway (IPC) |
   +---------+---------+                     +---------+---------+
             |                                         | Named Pipe (Win)
             |                                         | Unix Socket (Mac/Linux)
             v                                         v
   +-------------------+                     +-------------------+
   |                   |                     | liino-daemon Host |
   | Rust Shared Core  |                     | Tray / Proc Mgr   |
   | (Engine/Audio/Net)| <-------------------+---------+---------+
   +---------+---------+                               |
             |                                         v
             +--------------------+--------------------+
                                  |
                                  v
                    +---------------------------+
                    | OS Platform Adapters      |
                    | WASAPI / CoreAudio /      |
                    | PipeWire / Android / BT   |
                    +---------------------------+
```

### 职责边界铁律

1. **Rust 是唯一核心业务来源**：网络传输（TCP/UDP/USB/BT）、Protobuf 协议、会话状态机、Opus 编解码、Jitter Buffer、FEC、DSP（降噪/AEC/AGC/VAD）全部在 Rust 实现，禁止在 Dart 或 Kotlin 中维护第二套引擎。
2. **FRB 仅作低频控制与状态通道**：负责引擎启停、配置下发、设备/会话管理、节流后的低频状态流（如每秒 RTT/抖动/丢包率/电平包络），严禁高频 PCM 样本穿越 Dart ↔ Rust 边界。
3. **桌面端进程隔离与 GUI 内存释放**：
   - 桌面端由独立 `liino-daemon`（Rust Host）持有音频引擎、网络服务、蓝牙服务、系统托盘（原生托盘，不依赖 Flutter）与 IPC Server。
   - 用户关闭主窗口后，彻底退出 Flutter GUI 进程并销毁 Flutter Engine（释放 Dart Heap、Raster Cache 与 Skia/Impeller 显存/内存），后台音频通信与托盘保持运行；需要时由托盘通过进程管理器重新拉起 Flutter GUI。

## 3. 目标 Monorepo 工程结构

在 LocalSend Workspace 基础上演进为清晰的分层结构（按真实依赖拆分 Crate，避免过度碎片化）：

```text
liino/
├── app/                     # Flutter 统一客户端（MD3 Expressive UI + 平台工程）
├── packages/
│   ├── liino_api/           # FRB 绑定包（移动端直连 Rust / 桌面端走 CoreGateway）
│   └── liino_design/        # Material 3 Expressive Design Tokens 与组件库（规划）
├── crates/
│   ├── liino-protocol/      # Protobuf 消息定义与编解码
│   ├── liino-audio-core/    # 音频缓冲、RingBuffer、Opus、DSP、PureVox/AEC7
│   ├── liino-engine/        # 会话管理、传输抽象（LAN/USB/BT）、连接状态机
│   ├── liino-platform/      # OS 音频设备/虚拟麦克风/蓝牙适配层
│   ├── liino-frb/           # Flutter Rust Bridge 导出接口层
│   └── liino-daemon/        # 桌面端独立后台宿主、IPC Server 与原生托盘
├── docs/
│   ├── architecture/        # 架构与选型文档、ADR
│   ├── migration/           # MicYou 代码审计与分阶段迁移路线
│   └── memory/              # 各平台 Release 内存基线与回归记录
└── Cargo.toml / pubspec.yaml
```

## 4. 内存与性能硬性约束

- **有界数据结构**：Rust 侧 UDP/TCP 队列、Jitter Buffer、PCM RingBuffer、日志与统计历史均采用固定容量或环形缓冲区，禁止无界增长。
- **按需加载**：AI 降噪/AEC 模型（`micyou-infer`）、插件运行时（Native/WASM）仅在用户启用对应功能时初始化，关闭时释放。
- **UI 可见性原则**：音频电平/频谱可视化动画与定时器在页面不可见或窗口隐藏时立即暂停；桌面端关闭窗口即销毁 GUI 进程。
