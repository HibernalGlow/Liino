# 架构决策记录（ADR）

本目录记录 liino 的不可逆/高成本决策。每个 ADR 只回答一件事：**决定了什么、为什么、代价是什么、什么情况下会被推翻**。

状态约定：

- **Accepted**：已决定并已按此实现或正在实现。
- **Proposed**：推荐方案，等待确认后才能作为实现依据。
- **Superseded**：被更新的 ADR 取代。

| 编号 | 决策 | 状态 |
| :--- | :--- | :--- |
| [0001](0001-vendor-direct-dependency.md) | MicYou 以 submodule 放 vendor，直接 path 依赖，不复制 | Accepted |
| [0002](0002-android-build-shims.md) | Android 构建：arboard shim + minSdk 26 | Accepted |
| [0003](0003-mobile-native-engine.md) | 移动端沿用 MicYou 原生引擎（Kotlin/Swift），不迁到 Rust | Accepted |
| [0004](0004-desktop-daemon-hosts-core.md) | 桌面 daemon 内嵌 micyou-core server，Flutter 仅作 IPC 客户端 | Accepted |
| [0005](0005-bluetooth-rfcomm.md) | 蓝牙主传输采用 Classic RFCOMM + MicYou 帧格式 | Accepted |
| [0006](0006-wire-compat.md) | 复用 MicYou 端口/mDNS/协议，保持互通 | Accepted |
| [0007](0007-licensing.md) | 整体以 GPL-3.0-or-later 分发 | Accepted |
| [0008](0008-security-model.md) | v1 沿用 MicYou 的安全模型（局域网不鉴权，蓝牙依赖配对） | Accepted |
| [0009](0009-macos-bluetooth-bridge.md) | macOS 蓝牙通过 ObjC C-ABI shim 接入 daemon | Proposed |

未决细节与需要产品确认的问题见 [`../grilling.md`](../grilling.md)。
