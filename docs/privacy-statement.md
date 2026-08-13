# 隐私合规声明（P2-16，暂存文档）

> 2026-08-14 从 `AppScope/app.json5` 迁出：
> 本机 SDK（HarmonyOS 6.1.1 / API 24，DevEco 6.x）的 app.json5 schema
> 顶层只允许 `app` 一个属性，`privacy` 字段会导致 hvigor PreBuild 报
> `Schema validate failed (propertyNames: 'privacy')`，构建失败。
>
> 后续处理（按需二选一）：
> 1. 上架 AppGallery 时：隐私声明在 AGC 控制台 → 应用信息 → 隐私声明 填写，
>    无需写入 app.json5。
> 2. 若未来 SDK 版本支持 app.json5 privacy 字段（以当时 schema 为准），
>    可把以下内容原样迁回。
>
> 本项目目前仅自用侧载、不上架，此声明不影响构建与运行。

## publicPrivacyStatement

- en-US: HarmonyVPN routes your device's network traffic through a user-configured proxy server to help you access the open Internet. We do not collect, store, or transmit any personal data beyond what is strictly necessary for the proxy functionality (e.g. server connection logs you can clear at any time). All subscription URLs and configurations are stored locally on your device.
- zh-CN: HarmonyVPN 将设备的网络流量通过用户配置的代理服务器转发，帮助您访问开放的互联网。我们不会收集、存储或传输任何超出代理功能必需范围的个人数据（如您可随时清理的连接日志）。所有订阅 URL 和配置仅存储在您的设备本地。

## publicPrivacyPolicy

- en-US: https://example.com/privacy-policy-en.html
- zh-CN: https://example.com/privacy-policy-zh.html
