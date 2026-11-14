# Licensing

liino 是 LocalSend 的衍生作品，并直接复用 MicYou 的 GPL 代码。不同部分的许可如下：

| 范围 | 许可证 | 说明 |
| :--- | :--- | :--- |
| **整体分发**（App、daemon、APK） | **GPL-3.0-or-later** | 见根目录 `COPYING`；完整对应源码为本仓库 + `vendor/` submodule pin |
| 根 `LICENSE` 与 LocalSend 派生文件 | Apache-2.0 | 保留原始版权头；这些文件并入 GPLv3 整体作品 |
| `crates/liino-core` | Apache-2.0 | 只包含 liino 自有领域类型，不依赖 GPL 代码 |
| `crates/arboard-shim` | MIT OR Apache-2.0 | 仅用于让 Android 构建通过 |
| `crates/liino-{protocol,engine,audio-core,infer,daemon}` | GPL-3.0-or-later | 源自 MicYou 或与 GPL 代码链接 |
| `packages/liino_api` | GPL-3.0-or-later | 直接依赖 `micyou-core` |
| `vendor/micyou` | GPL-3.0-or-later with MicYou Plugin Exception | 见 `vendor/micyou/LICENSE` |
| `vendor/micyou-ios` | GPL-3.0-or-later with MicYou for iOS Additional Permission | 见该子模块的 `LICENSE` 与 `LICENSE-EXCEPTION` |

## 分发注意

- 提供完整源码（含 submodule 对应提交）即可满足 GPLv3 的源码义务。
- App Store 的 DRM/签名条款与 GPLv3 存在冲突风险；上架前需单独评估。
- 本文件是工程约定，不构成法律意见。

相关决策：[ADR-0007](docs/architecture/adr/0007-licensing.md)。
