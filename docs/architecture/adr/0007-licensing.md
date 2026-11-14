# ADR-0007：整体以 GPL-3.0-or-later 分发

- 状态：Accepted（2026-11-14 所有者确认；以下为工程决策，非法律意见）
- 日期：2026-11-14

## 背景

- 本仓库基座 LocalSend 的根 `LICENSE` 是 **Apache-2.0**。
- MicYou 是 **GPL-3.0-or-later with MicYou Plugin Exception**。
- liino 现在直接 path 依赖 `micyou-core`，并把其代码链接进 `libliino_api` 与桌面 daemon。
- `packages/liino_api` 当前标注 Apache-2.0，但已依赖 GPL 代码，标注与实际不符。

Apache-2.0 与 GPLv3 兼容的方向是“Apache 代码可以并入 GPLv3 作品”，反向不成立；链接后的整体分发必须满足 GPLv3。

## 决策（推荐）

1. liino 的**整体分发**（App、daemon、APK）采用 **GPL-3.0-or-later**。
2. 保留 LocalSend 派生文件的 Apache-2.0 版权头；在仓库根增加 `COPYING`/说明，明确“整体作品为 GPLv3，部分文件仍为 Apache-2.0”。
3. 把 `packages/liino_api`、`apps/liino_app` 等会链接 MicYou 代码的包改为 `GPL-3.0-or-later`；`crates/liino-core` 若保持 Apache，必须确保不依赖 GPL 代码。
4. 分发时提供完整对应源码（本仓库 + vendor submodule pin），满足 GPLv3 的源码提供义务。
5. 如未来需要闭源或 App Store 分发，必须重新评估（GPLv3 与 DRM/签名限制存在冲突）。

## 代价

- 不能再以 Apache-2.0 宣传整个产品。
- App Store 分发存在合规风险；F-Droid、直接下载不受影响。
- 需要法务复核 MicYou Plugin Exception 对插件/衍生作品的具体要求。

## 备选方案

- **进程隔离**：liino GUI 保持 Apache，MicYou 代码只存在于独立 GPL daemon 进程，通过 IPC 通信。法律边界不清，且移动端无法这样做；不推荐作为主方案。
- **不使用 MicYou**：与项目目标冲突，否决。

## 已确认

- 所有者接受整体 **GPL-3.0-or-later**。
- 保留 LocalSend 派生文件的 Apache-2.0 头，并在根目录新增 `COPYING` + `LICENSING.md` 说明。
