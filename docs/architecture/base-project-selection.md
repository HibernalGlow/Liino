# 基座项目选型报告（Base Project Selection）

## 1. 评估维度与候选项目对比

为避免从零搭建跨平台 Flutter + Rust + FRB 工程基础设施，本次调研从技术栈真实性、FRB 集成度、目标平台支持、桌面打包流水线、Rust Core 解耦度、维护活跃度、许可证兼容性与内存/依赖复杂度等维度，对比了三个候选项目：

| 评估维度 | [LocalSend](https://github.com/localsend/localsend) | [RustDesk](https://github.com/rustdesk/rustdesk) | [flutter_rust_bridge 官方模板](https://github.com/fzyzcjy/flutter_rust_bridge) |
| :--- | :--- | :--- | :--- |
| **开源许可证** | Apache-2.0（宽松，无强传染性） | AGPL-3.0（强传染性网络服务条款） | MIT（极宽松） |
| **Flutter + Rust 真实性** | 真实生产项目（Dart Workspace + Cargo Workspace） | 真实生产项目（Flutter + Rust + C++） | 官方脚手架与示例工程 |
| **FRB 版本与集成** | `flutter_rust_bridge` v2.12.0（`packages/localsend_isolates`） | FRB v1 风格（`flutter_ffi.rs` 手工胶水层） | `flutter_rust_bridge` v2.14+ 最新标准 |
| **目标平台覆盖** | Android / iOS / macOS / Windows / Linux | Android / iOS / macOS / Windows / Linux | 全平台支持（需自行补全桌面打包） |
| **桌面构建与打包** | 成熟（DMG / MSIX / EXE / AppImage / DEB / RPM） | 复杂（依赖 `build.py` 与 `vcpkg` C++ 库） | 仅提供基础 `flutter build` 骨架 |
| **独立 Rust Core** | 有（`packages/core` + `cli/` + `server/`） | 耦合严重（`src/` 与远程桌面音视频捕获紧耦合） | 无业务 Core（需从零组织） |
| **外部 C/C++ 依赖** | 极少（纯 Rust 为主） | 重度依赖 `vcpkg`（`libvpx` / `libyuv` / `aom`） | 无 |
| **维护活跃度** | 极高（Flutter 3.47.x，持续发版 v1.18.2） | 极高（持续发版 v1.5.3） | 极高（FRB v2 主力维护） |
| **跟进上游难度** | 低（结构清晰，Workspace 解耦） | 高（代码库庞大，历史包袱重） | 极低（标准模板） |

## 2. 选型结论

**选定 [LocalSend](https://github.com/localsend/localsend) 作为 `liino` 的上游技术基座**，并结合 [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) v2 的官方最佳实践进行精简与定制：

1. **工程结构契合**：LocalSend 采用 Dart Workspace（根 `pubspec.yaml`）+ Cargo Workspace（根 `Cargo.toml`）的 Monorepo 组织方式，天然适配 `liino` 将 Rust 核心拆分为多个独立 Crate 并通过独立桥接包暴露给 Flutter UI 的架构规划。
2. **版本与构建链路对齐**：LocalSend 上游已升级至 Flutter 3.47.x / Dart 3.11+ 与 `flutter_rust_bridge` 2.12.0，并提供完整的 Android、Windows、macOS、Linux CI/CD 发布流水线（`.github/workflows/ci.yml` 与 `release.yml`）。
3. **排除了 RustDesk 的原因**：RustDesk 强依赖 `vcpkg` C++ 生态（`libvpx`、`libyuv`、`aom`），且业务逻辑与远程桌面键鼠/屏幕捕获深度耦合，引入后会带来沉重的编译复杂度与 AGPL-3.0 许可证约束。

## 3. 克隆与上游隔离策略

- **本地克隆路径**：`/Users/glow/Base/Code/Prometheus/Liino`（已配置只读远端 `upstream` -> `https://github.com/localsend/localsend.git`，push URL 设为 `no_push` 防止误推）。
- **开发分支**：基于 `upstream/main` 创建本地 `liino` 分支，保留完整原始 Git 历史与 `LICENSE`。
- **演进原则**：不直接引入 LocalSend 的文件传输业务逻辑（如 `in_app_purchase`、`wechat_assets_picker`、`gal` 等）；在 `liino` 分支上逐步以 `liino` 最小验证工程与音频核心替换原 `app/` 与 `packages/core` 业务内容，同时保留其多平台打包、托盘/窗口管理脚手架与 Workspace 规范。

## 4. 许可证兼容性说明

- **基座许可证**：LocalSend 采用 **Apache-2.0**；`flutter_rust_bridge` 采用 **MIT**。
- **业务参考来源**：[MicYou](https://github.com/MicYou-Dev/MicYou) 采用 **GPL-3.0-or-later (with MicYou Plugin Exception)**。
- **合规策略**：若后续阶段直接复用 MicYou 的 Rust 源码（如 `micyou-infer`、`micyou-audio`、`micyou-protocol`），`liino` 整体分发需遵循 **GPL-3.0-or-later**（Apache-2.0 与 GPL-3.0 单向兼容，合并后整体受 GPL-3.0 约束），并在 `LICENSE` 与 `THIRD_PARTY_NOTICES` 中完整保留各方版权声明。
