# ADR-0004：桌面 daemon 内嵌 micyou-core，Flutter 仅作 IPC 客户端

- 状态：Accepted（设计已定，实现待完成）
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
