# ADR-0004：桌面 daemon 内嵌 micyou-core，Flutter 仅作 IPC 客户端

- 状态：Accepted（设计已定；2026-11-15 方案 B 核心引擎迁移已实现并验证：daemon 内嵌 vendored micyou-core 服务端生命周期，vendor 零改动；presence/role 复制件迁移、IPC 事件订阅、原子实例锁待完成；A/B 评估见「方案评估」）
- 日期：2026-11-14

## 背景

产品要求：关闭桌面窗口后 Flutter 进程完全退出、内存释放，而音频与托盘继续运行。MicYou 的 Rust core 本身就是一个无 UI 的 server（`micyou-core::server::ServerState` + `start_server(StartRequest)`），具备 mDNS、TCP 控制、UDP 音频、DSP 与输出管理。

如果 Flutter 进程内直接跑 FRB 引擎，关闭窗口就无法释放 Flutter/Dart/Skia 内存，也无法在窗口关闭后继续服务。

## 决策（推荐）

1. `liino-daemon` 成为 **macOS 与 Windows** 桌面端唯一引擎宿主（Linux 后续）：内嵌 `micyou-core`，持有 `ServerState`、mDNS、TCP/UDP、音频输出、插件宿主。
2. Flutter GUI **只通过 IPC**（macOS/Linux Unix socket，Windows Named Pipe）读写状态；桌面端删除“IPC 失败就回退进程内 FRB”的逻辑，避免同一端口被两个引擎绑定。
3. IPC 由“请求/响应”扩展为“请求/响应 + 事件订阅”：
   - 请求：`get_status`、`get_peers`、`connect_peer`、`disconnect_peer`、`set_role_mode`、`set_transport`、`start_link`、`stop_link`、`shutdown_daemon`。
   - 事件：连接/断开、peer 上下线、节流后的统计（RTT/Jitter/丢包/码率/缓冲水位）、错误。
   - 帧上限 16 KiB；事件队列有界，慢客户端丢弃旧统计而不是阻塞引擎。
4. 托盘、登录自启、单实例锁都由 daemon 负责；GUI 退出后 daemon 继续运行。
5. GUI 启动时若 daemon 不在，按 `LIINO_DAEMON_BIN` → App 内嵌 `Contents/Resources/liino-daemon` → 工作区 `target/release` 顺序拉起。

## 代价

- 需要把 `micyou-core` 的 `ServerEvents` / `HostIntegration` 适配成 liino 的事件与托盘实现。
- IPC 协议要版本化，避免 GUI/daemon 版本错配。
- 调试链路变长（GUI → IPC → daemon → core）。

## 备选方案

- GUI 内嵌引擎：实现简单，但关闭窗口无法释放内存，直接违反产品约束；否决。
- 每次关闭窗口重启 daemon：会中断音频，否决。

## 验收

- 关闭窗口后 GUI 进程消失、daemon 与音频会话存活（已有初步验证）。
- GUI 重启后通过 `get_status` 恢复完整状态，不重复拉起 daemon。

## 实现现状（2026-11-15 核实）

- **daemon 已存在**：`crates/liino-daemon` 已有 JSON-line IPC（`ipc.rs` 的 `IpcRequest`/`IpcResponse`，16 KiB 帧上限、队列深度 128、Unix socket / Windows Named Pipe），命令面与本 ADR 决策 3 一致（get_status/get_peers/connect_peer/set_role_mode/set_transport/start_link/stop_link/shutdown_daemon + 蓝牙）。多客户端**连接**已支持（每连接 `tokio::spawn`）。
- **缺口①：核心引擎已迁移到 micyou-core（2026-11-15 实现并验证，方案 B）。** `liino-daemon/Cargo.toml` 现 path 依赖 vendored `micyou-core`（`default-features = false`，不引 headless-host 以免拖入 global-hotkey/open/notify-rust）；`StartLink`/`StopLink`/`ShutdownDaemon` 走真实 `ServerState::new` + `server::start_server`/`stop_server` + `service::close_output_device`，`handle_request` 改 async。liino 自有薄层 `engine.rs` 实现 `ServerEvents`（`LiinoEventSink`，快照 connected/peer/mute/monitoring/metrics）与 `HostIntegration`（`LiinoHost`，OS 集成暂 log，待决策 4）；`GetStatus` 指标改读 `server.network_stats.to_metrics`。**验证**：`cargo check --offline` / `cargo test`(2/2) / build 绿；IPC smoke（ping→get_status→start_link→get_status→stop_link→shutdown）`is_running` False→True→False，收到真实 `server_stopped` 事件；StartLink 期间 daemon PID 实监听 TCP `*:8554`(IPv4+IPv6) + UDP `*:8555`；vendor submodule 干净（零上游改动，B 的定义性质）。**残留**：presence/role/capabilities 仍跑 `liino-engine/liino-core/liino-platform` 复制件（ADR-0001 待删），未迁到 micyou-core；`LiinoHost` 的托盘/热键/插件窗口/通知 OS 集成待决策 4。
- **缺口②：IPC 只有请求/响应，无事件订阅/server-push。** `run_ipc_server` 每连接读一行→dispatch→回一行，无 Subscribe、无事件广播；GUI 现靠轮询（grilling Q10「1–2 s 轮询兜底」）。决策 3 的「+事件订阅」尚未落地。
- **实例锁偏弱**：当前 `remove_file(endpoint)` + `bind`，无原子实例锁，双 daemon 并发启动有 TOCTOU 竞争。

## 方案评估：独立 daemon crate vs 演进 micyou-cli（2026-11-15）

外部建议提出「不建独立 daemon crate，直接把 vendored `micyou-cli` 演进成 daemon，复用其 `serve --jsonl`」。评估后**不采用，维持独立 `liino-daemon` crate**（与本 ADR 决策 1、ADR-0001 一致）。

两条执行链：
- **A（演进 micyou-cli）**：改 vendor submodule 内的上游 `micyou-cli`，加 daemon 生命周期 + 多客户端 IPC，用该二进制当 liino daemon。
- **B（独立 crate）**：`liino-daemon` 为 liino 自有薄层，path 依赖 `micyou-core`，嵌 `ServerState` + `start_server`，自持生命周期/IPC/托盘/锁；上游 `micyou-cli` 不动。

**选 B 的理由**：
1. **ADR-0001 默认不改上游**：vendor 是 pin 死的 submodule，「新功能放 liino 薄层，fork 仅在需改上游行为时启用」。A 必须 fork/打补丁，直接违反该原则。
2. **micyou-core 已留好扩展缝**：`HostIntegration` trait（`host/mod.rs`）+ `HeadlessHost` + `ServerState` 正是为 B 设计——liino 实现 trait 即可接入托盘/插件窗口/IPC，零上游改动；A 反而要改上游函数体。
3. **micyou-cli 的可复用价值是「设计」不是「crate」**：`jsonl.rs` 的 protocol/transport 拆分、v1 命令/响应/id 关联、有界事件队列、统计节流，可在 liino 自有 IPC 里参照实现，不必动上游。core 两条路都经 path 依赖复用，A 并不省 core。
4. **A 的「复用」是部分的**：micyou-cli 的 JSONL 走 stdin/stdout，是父子进程管道——GUI（父）退出即 EOF、daemon 随之停止（稿子自己也指出这点）。而本 ADR 要求关窗后 daemon 续命，**必须**把传输换成可断可重连、与进程生命周期解耦的 Unix socket/Named Pipe，这就要重写上游传输层；还拖入 CLI 专属包袱（命令解析/logger/plugin_cmds/mode_lock Cli）。**注意：强制项是「stdin/stdout→socket」（生命周期逼出来），不是「多客户端」**——liino 当前仅 Flutter GUI 一个客户端（无 liino-tui/cli crate；current-code-audit 把 micyou-cli/tui 定为「参考借鉴」），单客户端 socket 即满足本 ADR；GUI+CLI+TUI 同时连是上游愿景，非 liino 既定需求。
5. **上游同步成本**：A 让每次 MicYou 升级都背 micyou-cli 的合并冲突；B 保持 vendor 干净，升级只跑回归。

**何时才考虑 A**：liino 战略上决定整体 fork MicYou（ADR-0001 备选）时。当前跟踪上游 submodule，B 正确。许可证两条路皆 GPL（ADR-0007），无差异。

## 可复用上游细节（参考实现，不改上游）

来自对 vendor v2.2.0 的核实，供 daemon 迁移与 IPC 事件订阅参照：
- **JSONL 协议/传输拆分**（`micyou-cli/src/jsonl.rs`）：`protocol`（解析/响应/事件/命令分发）与 `transport`（stdin/stdout、Unix socket、Named Pipe）分离；v1 帧 `{v,type,id,name,payload}`、响应 `{v,type,id,ok,payload|error}`；有界事件队列 + 统计节流 + 慢客户端丢弃。liino IPC 事件订阅照此形状补。
- **插件窗口转发**：`HostIntegration::open_plugin_panel`（`host/mod.rs:34`）在 `HeadlessHost` 是 no-op（`headless.rs:189`）；liino 的 HostIntegration 实现把它转成 IPC 事件发给 GUI，由 Flutter 开窗——插件 DSP/状态留 daemon，UI 归 GUI。
- **原子实例锁**：用 `create_new` 原子创建锁文件 + IPC 地址信息，替换当前 `remove_file+bind`；daemon 独占服务、客户端可断可重连（liino 当前仅 Flutter GUI 一个客户端；上游 mode_lock 的 Gui/Cli/Tui 三模式互斥不再适用）。多客户端同时连接非 liino 当前需求。
- **托盘迁移**：上游托盘在 Tauri 进程（`src-tauri/host.rs TauriHost`、`app.rs`）；liino 托盘归 daemon（决策 4），菜单至少 显示/隐藏 GUI、连接状态、静音、断开、退出 Host。
