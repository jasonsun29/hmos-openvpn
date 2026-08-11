# ADR-0001: 复用 ClashBox proxy_core 核心层，UI 从零搭建

**Status:** accepted
**Date:** 2026-08-11
**Deciders:** Jason（拍板）、Hermes Agent、三Agent评审（GLM-5.2/Kimi-K3/MiniMax-M3）

## Context

hmos-openvpn 要在 HarmonyOS NEXT 上复刻 Clash Verge。代理核心 mihomo 必须编译为鸿蒙 arm64 `.so` 经 NAPI 调用（鸿蒙沙箱不允许独立 daemon）。交叉编译 mihomo 需要非官方的 go-ohos 工具链（OpenHarmony SIG 已归档，生产靠 yourblacksky fork Go 1.25.12，须源码编译），这是全项目最高技术风险点。ClashBox（⭐4.2k）已用同一架构跑通，且其 `proxy_core` 是独立的 Apache-2.0 鸿蒙库模块（含 mihomo 编译产物 libflclash.so + Go 桥接层 + C++ NAPI 桥 + 权限声明），与其 UI（entry 模块，123 个 .ets）完全解耦。

## Decision

**直接复用 ClashBox 的 `proxy_core` 模块作为核心层；ArkTS UI 层完全从零搭建，组件结构对照 Clash Verge 的 React 组件树翻译，不采用 ClashBox 的任何 UI 代码。**

## Rationale

三个选项：
1. **复用 proxy_core + UI 从零**（选定）：核心编译链路、NAPI 桥、权限声明全现成且已被 ClashBox 大量用户验证；避开 go-ohos 自建编译这个最大坑；工期最短。proxy_core 是独立模块、Apache-2.0 许可允许衍生与再分发，合规。Kimi 评审明确"重建成本高于裁剪，推荐"。
2. **完全从零自建核心编译链路**：掌控力强，但把 go-ohos 工具链这个 🔴 最高风险全自己扛，且要重写 NAPI 桥接。被否。
3. **整体 fork ClashBox 含 UI 再改**：ClashBox 的 UI 是 Surfboard 风格，与要复刻的 Clash Verge 完全不同，改 UI 不如从零搭干净。被否。

三Agent R1 评审一致倾向前者，Jason 拍板确认。

## Consequences

- 正面：M0 最大风险（核心编译）转为"复现验证"而非"从零攻关"；核心能力直接可用。
- 代价：核心与 ClashBox 强绑定，跟随其升级节奏；存在"能力空心化"风险（若丧失改 Go 层能力）——已通过风险登记册缓解：go-ohos 本地复现 build 能力作为 M0–M1 必做验证、patch SLA（上游 14 天无响应则本地建分支）、fallback tun2socks 保底。
- 迁移：proxy_core 以 `file:../proxy_core` 依赖方式引入工程；上游 .so 用 sha256 锚定 + ABI 版本握手自检。
