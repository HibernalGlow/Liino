# Phase 1 / Phase 3 内存基线与编译验证记录（Memory Baseline）

## 1. 测试环境

- **主机平台**：macOS Apple Silicon (`darwin-arm64`)
  - Rust 工具链：`cargo 1.99.1` / `rustc 1.99.1`（Homebrew）
  - Flutter / Dart 工具链：Flutter `3.47.4` / Dart `3.13.7` / `flutter_rust_bridge_codegen 2.12.0`
  - 测量工具：`/usr/bin/time -l`
- **Android 真机**：`24129PN74C`（设备序列号 `3ade0ba3`，`android-arm64`，Android 17 / API 37）
  - 测量工具：`adb -s 3ade0ba3 shell dumpsys meminfo app.liino.liino_app`

## 2. macOS arm64 Rust Release 基线

| 验证项 | 命令 / 产物 | 实测结果 |
| :--- | :--- | :--- |
| Rust 核心单元测试 | `cargo test -p liino-core -p liino-engine -p liino-platform -p liino-daemon` | 全部通过（`liino-core` 2、`liino-engine` 78、`liino-platform` 2、`liino-daemon` 2） |
| `liino_api` Release 库 | `cargo build --release -p liino-core -p liino_api` | `libliino_api.dylib` = **857 KB**；`libliino_api.a` = **10 MB** |
| `liino-daemon` Release 二进制 | `cargo build --release -p liino-daemon` | `target/release/liino-daemon` = **1.1 MB** |
| Rust Core Release 进程基线 | `/usr/bin/time -l ./target/release/examples/mem_probe` | `maximum resident set size` = **1,867,776 B (~1.78 MiB)**；`peak memory footprint` = **1,261,952 B (~1.20 MiB)** |

## 3. Android arm64 真机 Release 基线（`24129PN74C` / Android 17）

- **测试包**：`apps/liino_app/build/app/outputs/flutter-apk/app-release.apk`（**17 MB**，`Nov 15 14:20` 编译，含 `jniLibs/arm64-v8a/libliino_api.so` 2.51 MB）
- **冷启动耗时**：`TotalTime = 335 ms`，`WaitTime = 339 ms`
- **首页空闲内存（PID 30714，启动后 3s 采集）**：

| 指标 | PSS (KB) | RSS (KB) |
| :--- | ---: | ---: |
| **TOTAL** | **130,166 (~127.1 MiB)** | **266,576 (~260.3 MiB)** |
| Native Heap | 24,768 | 26,536 |
| Java Heap | 3,484 | 18,220 |
| Graphics (`EGL/GL/Gfx`) | 40,516 | 40,520 |
| Code | 33,180 | 156,256 |
| Stack | 1,628 | 1,636 |
| Private Dirty | 98,860 | — |

## 4. Android 活跃态内存（`AudioForegroundService` + `BluetoothRfcommServer`）

- **状态**：`AudioForegroundService` 运行中，`BluetoothRfcommServer` 已在 RFCOMM SCN `13` 进入 `STATE_LISTENING`（`Role: SENDER · Transport: BT RFCOMM · Buffer: 20 ms`，PID `31909`）
- **实测内存（`dumpsys meminfo app.liino.liino_app`）**：

| 指标 | PSS (KB) | RSS (KB) |
| :--- | ---: | ---: |
| **TOTAL** | **121,166 (~118.3 MiB)** | **253,504 (~247.6 MiB)** |
| Native Heap | 18,380 | 19,996 |
| Java Heap | 4,504 | 27,028 |
| Graphics (`EGL/GL/Gfx`) | 40,616 | 40,620 |
| Code | 26,468 | 139,624 |
| Stack | 1,032 | 1,044 |
| Private Dirty | 79,492 | — |

## 5. macOS Desktop `liino-daemon` + `liino_app.app` 联调与生命周期内存

- **IPC 端点**：`/tmp/liino-daemon.sock`（`liino-daemon` PID `14474`，`is_running: true`，`active_transport: bluetooth_rfcomm`，`virtual_mic_driver: BlackHole 2ch`）
- **测量工具**：`libc` `proc_pidinfo(PROC_PIDTASKINFO)`

| 阶段 | `liino-daemon` PID / RSS | `liino_app` GUI PID / RSS | 说明 |
| :--- | :--- | :--- | :--- |
| GUI 启动前 | `14474` / **14.12 MiB** | — | Daemon 独立常驻 |
| GUI 首次拉起 | `14474` / **14.27 MiB** | `32301` / **81.38 MiB** | IPC `get_status` 连接成功 |
| 关闭 GUI 进程后 | `14474` / **14.27 MiB** | 已退出（**0 / 释放 81.38 MiB**） | `ping` 仍返回同一 `pid: 14474` |
| 重新拉起 GUI | `14474` / **14.23 MiB** | `32314` / **80.92 MiB** | 成功重新挂载到同一 Daemon |

## 6. macOS ↔ Android 蓝牙 RFCOMM 实机联调（`glow-air` ↔ `Xiaomi 15` / `3ade0ba3`）

- **连接路径**：`liino_app.app` → `liino-daemon`（PID `42099`）→ `liino-bt-helper` → `IOBluetooth` → Android `BluetoothRfcommServer`（UUID `6C69696E-6F00-4B42-8C4C-6C69696E0001`）
- **实测结果**：
  - `list_bluetooth_devices` 成功枚举出 `{"address":"f0-2c-7b-fb-ca-9f","name":"Xiaomi 15"}` 等 11 条已配对记录。
  - `connect_bluetooth("f0-2c-7b-fb-ca-9f")` 返回 `{"type":"ok"}`，`get_status` 显示 `"bluetooth_address":"f0-2c-7b-fb-ca-9f"`。
  - Android `logcat -d -s liino-bt` 记录：`11-15 15:03:40.966 31909 4093 I liino-bt: channel accepted from DC:93:96:12:9B:34`（服务端随后写出 `LIINO-BT-READY\n`；`liino-daemon` 当前 `BluetoothLink` 为原始字节流通道占位，尚未接入帧化音频/echo 协议）。
- **连接态内存**：
  - macOS `liino-daemon`（PID `42099`）：**19.78 MiB RSS**
  - Android `app.liino.liino_app`（PID `31909`）：**TOTAL PSS = 100,882 KB (~98.5 MiB)** / **TOTAL RSS = 219,788 KB (~214.6 MiB)**

## 7. 尚未验证与环境限制

1. **蓝牙音频帧传输**：`BluetoothRfcommServer` 与 `BluetoothLink` 当前完成 RFCOMM 通道建立与服务端就绪握手（`LIINO-BT-READY\n`），`micyou-core` 蓝牙帧传输层尚未接入。
2. **Windows / Linux 实机基线**：待在对应平台补测。
