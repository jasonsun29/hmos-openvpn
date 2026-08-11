# ADR-0002: 单进程模型 + NAPI 直连（禁用 RESTful external-controller）

**Status:** accepted
**Date:** 2026-08-11
**Deciders:** Hermes Agent、三Agent评审共识（R1/R2）

## Context

Clash Verge 桌面端架构是 `前端 ↔ RESTful API(:9090) ↔ 独立 mihomo 进程`。鸿蒙 NEXT 沙箱不允许独立 native daemon，核心必须编译为 `.so` 内嵌应用进程。这带来两个必须决策的问题：① VpnExtensionAbility 与 UIAbility 是否同进程？② 数据通路走 NAPI 直连还是 mihomo 内置 RESTful？

R1 评审（MiniMax 阻断-A/B、Kimi 1-2）指出：若启用进程隔离，fd 无法跨进程传递、UI 侧拿到空核心，数据通路崩塌；NAPI 是同步 C API，跨线程推送机制必须明确。

## Decision

1. **单进程模型**：所有组件（UIAbility + VpnExtensionAbility + libflclash.so）运行在应用同一进程，不启用 `isolationProcess`。TUN fd 由 VpnExtensionAbility.onCreate 在本进程创建，直接传同进程 startTun(fd)，不跨进程。
2. **NAPI 直连，禁用 RESTful**：Service 层数据全部走 NAPI Bridge 调 .so 导出函数，不启用 mihomo external-controller（不设 9090 端口）。调试时可临时起 127.0.0.1 回环 external-controller（仅回环、不带鉴权对外）。
3. **跨线程推送走 TSFN**（napi_threadsafe_function）；Go panic 所有导出函数 `defer recover`（硬性要求）。

## Rationale

- 同进程：ClashBox 实证可行；避免跨进程 fd 传递与空核心问题（R1 共识）。
- NAPI 直连：内嵌模式下 RESTful 需 listen 端口，有端口冲突与无鉴权暴露风险；NAPI 省一次 IPC、延迟更低（ClashBox 实证）。
- 放弃 RESTful 的代价已知并接受：~40 个函数需在 Go 侧包装为 ohos-napi 导出，mihomo 升级时同步桥接层（因复用 proxy_core，跟随其节奏）。

## Consequences

- Go runtime 单进程不可重启约束（c-shared 库 dlclose 后重载必崩）：所有配置变更必须进程内热加载解决，否则只能进程重启（隧道必断+UI 重启）。由此衍生配置变更影响分级 L1–L4（见设计文档 §3.5.3）。
- 线程/事件模型、错误码模型、核心状态机、反馈回路均在设计文档 §3.5–§3.9 固化。
