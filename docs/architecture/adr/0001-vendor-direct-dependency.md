# ADR-0001：MicYou 直接依赖，不复制

- 状态：Accepted
- 日期：2026-11-14
- 关联：`docs/migration/upstream-reuse.md`

## 背景

早期为了验证技术路线，把 MicYou 的 protocol / infer / audio / engine 复制成了 `crates/liino-*`。结果是同一套逻辑有两份，MicYou 上游修复无法自动获得，长期维护成本随功能增长迅速上升。

产品约束：**除蓝牙和 Flutter UI 外，其余能力优先复用 MicYou**。

## 决策

1. MicYou 主仓库与 iOS 仓库以 git submodule 放在 `vendor/micyou`、`vendor/micyou-ios`，由主仓库锁定提交。
2. 根 `Cargo.toml` 使用 `exclude = ["vendor"]`，让 vendor 内的 crate 按 MicYou 自己的 workspace 解析 `workspace = true`。
3. 需要哪个 crate 就直接写 path 依赖，例如：

   ```toml
   micyou-core = { path = "../../vendor/micyou/tauri-app/crates/micyou-core", default-features = false }
   ```

4. 新功能不再复制 MicYou 源码；适配逻辑放在 liino 自己的薄层（`liino-core`、daemon、FRB、平台桥）。
5. 已经存在的复制件标记为临时件，在 daemon / 移动端切换到 vendor 后删除。

## 代价

- 构建前必须 `git submodule update --init --recursive`，CI 需要同步调整。
- MicYou 上游 API 变动会直接传导到 liino；升级需要跑完整回归。
- 二进制体积与依赖数量增加（FRB `.so` 从 1.1 MB 增至 2.2 MB）。
- 许可证约束（见 ADR-0007）。

## 备选方案

- **继续复制**：可控但双份维护，已否决。
- **git dependency**：无法本地 pin + 打小补丁，且离线构建不稳定，否决。
- **维护 fork**：在需要修改上游行为时再启用；当前优先通过 shim/适配层解决。

## 验收

- `packages/liino_api` 已直接依赖 `micyou-core`，host 与 Android arm64 均编译、链接通过。
- `cargo test -p liino-engine -p liino-daemon` 保持通过。
