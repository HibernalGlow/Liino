# ADR-0002：Android 构建约束与 shim

- 状态：Accepted
- 日期：2026-11-14

## 背景

直接依赖 `micyou-core` 后，Android 构建遇到两个硬阻塞：

1. `micyou-core` 无条件依赖 `arboard`（只用于插件剪贴板 API），而 `arboard 3.7` 没有 Android 后端，编译报 `platform::Set` / `platform::Clear` 不存在。
2. `micyou-audio` 的 cpal Android 后端链接 `libaaudio`；NDK 只为 API 26+ 提供该库，`aarch64-linux-android24-clang` 链接失败。

liino 不使用 MicYou 的插件剪贴板 API。

## 决策

1. 新增 `crates/arboard-shim`（包名 `arboard`，版本 3.7.0），在根 `Cargo.toml` 用 `[patch.crates-io]` 全局替换。API 与真实 crate 对齐，所有调用返回 “clipboard is unavailable in liino builds”。
2. `apps/liino_app` 的 `minSdk` 固定为 **26**；`tool/build_android_rust.sh` 使用 `API=26` 的 clang wrapper。
3. 不修改 `vendor/` 子模块；上游若将 `arboard` 改为可选依赖，可删除 shim。

## 代价

- 桌面端插件剪贴板功能不可用（当前未启用插件运行时）。
- 放弃 Android 6/7（API 24/25）设备；MicYou 自身标称 minSdk 24，但其 Android 端不使用 cpal。
- shim 版本号需要跟随 `arboard` 主版本，升级 vendor 时检查。

## 备选方案

- 给 MicYou 提 PR 把 `arboard` 设为 optional：最优但取决于上游，暂不阻塞。
- 维护 fork：暂不采用（见 ADR-0001）。
- 降低到 API 24：链接期无 `libaaudio`，不可行。

## 验收

- `aarch64-linux-android` release 链接通过，`.so` 2.2 MB；APK 18.2 MB，`minSdkVersion=26`。
