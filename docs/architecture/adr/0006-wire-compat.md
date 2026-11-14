# ADR-0006：复用 MicYou 的端口、mDNS 与线协议

- 状态：Accepted
- 日期：2026-11-14

## 背景

直接依赖 `micyou-core` 后，网络层事实标准是 MicYou 的：

- TCP 控制端口 `9123`，UDP 音频端口 `9124`（`liino-protocol` 复制件同值）。
- mDNS 服务类型 `_micyou._tcp.local.`，Web 模式 `_micyou-web._tcp.local.`。
- `proto/network.proto` 的 `MessageWrapper` / `AudioPacketMessage` 等消息。

如果 liino 换端口或改协议，就无法与 MicYou 设备互通，也失去“复用上游”的最大价值；但完全沿用会与已安装的 MicYou 抢占端口，并让用户误以为两者是同一产品。

## 决策（推荐）

1. **保持线协议与端口不变**：liino 能与 MicYou 设备互相发现、连接、传音频。
2. mDNS 继续使用 `_micyou._tcp.local.`；v1 不新增 `_liino` 服务类型，避免发现列表出现重复条目。
3. 需要 liino 专有字段时，只在 protobuf 中追加 `optional` 字段，不复用/改变既有字段语义。
4. 品牌与识别通过设备名、`about` 信息与 UI 呈现区分；协议层不区分。
5. 发布说明中明确：与 MicYou 同时运行时只能有一个占用 `9123/9124`，建议退出来源不明的旧实例。

## 代价

- 协议兼容成为长期约束：升级 MicYou 时不能随意破坏旧客户端。
- 与 MicYou 同时运行时端口冲突（可通过检测已占用并提示解决）。
- 蓝牙是新增传输，不在此协议兼容范围内，但帧格式沿用同一 protobuf。

## 备选方案

- 独立端口/服务类型：隔离清晰，但无法互通，且需要两套发现逻辑；暂不采用。
- 双协议并存：维护成本高，Phase 5 再评估。

## 验收

- liino 手机端能被 MicYou 桌面端发现并建链（或反向），音频可播放。
- 同时安装 MicYou 时给出明确的端口占用提示。
