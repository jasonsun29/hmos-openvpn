# HarmonyOS VPN（Clash Verge 像素级复刻）项目上下文

## 项目目标
在鸿蒙系统（HarmonyOS NEXT）上做一个 VPN 应用，UI/交互像素级复刻 Clash Verge Rev（v2.5.3，已克隆研究）。

## 研究基线（2026-08-11 建立）
- 参考实现仓库已克隆：~/harmony-vpn-research/clash-verge-rev（v2.5.3）
- 前端：React + MUI，384 个源文件；后端：Tauri/Rust 包裹 mihomo 核心
- 八大页面：home/proxies/profiles/connections/rules/logs/unlock/settings
  （profiles 1066行最复杂，unlock 503行，layout 485行）
- 窗口规格：默认 940×700，最小 520×520（→ 鸿蒙平板上可直译，手机需适配方案）
- 主题色已提取：亮色 primary #007AFF / 背景 #F5F5F5；暗色 #0A84FF / #2E303D（详见 _theme.tsx）
- 布局：左侧导航栏（可折叠、可拖拽排序）+ 内容区，iOS 风格圆角卡片

## 技术可行性（调研完成 2026-08-11，详见 ~/harmonyos-vpn-research.md）
- 路线A（推荐）：VpnExtensionAbility(API 11+) + mihomo 编译为 .so 走 NAPI 调用；不能跑独立 daemon，必须 .so 动态库
- 关键参照：ClashBox(⭐4.2k, github.com/xiaobaigroup/ClashBox) 已跑通此架构（libflclash.so=NAPI），UI 用 ArkUI+Navigation；鸿蒙落地照它，功能清单照 Clash Verge
- 核心编译：Go→ohos_golang_go c-shared 实验性；FlClash/meta kernel 更成熟；备选 Rust/C++ FFI
- 已知限制：API 23 前 VpnConfig.routes 不生效（我们目标 23+ 规避）；后台保活有挑战；MANAGE_VPN 权限待确认
- ClashBox 完整源码已 clone（~/harmony-vpn-research/ClashBox master 分支）：proxy_core/src/flclash 是 Go 桥接层；core 子模块=mihomo（上游 xfz347/Clash.Meta 的 **ohos 分支**，主分支已被改作他用，707 文件）；gvisor-ohos 子模块已就位（648 文件）；编译链路=go-ohos 工具链 + build.sh(GOOS=linux/cgo c-shared/-tags "ohos with_gvisor")，OHOS_NATIVE_HOME 路径与本机一致；NAPI 接口面 ~40 函数（initClash/startTun/getProxies/getTraffic/getConnections/updateConfig 等，走 ohos-napi 的 js.Env/js.Value 桥，非标准 cgo export）

## 开发环境（2026-08-11 全部就位）
- Mac mini：DevEco Studio 已装，CLI 工具链已配 ~/.zshrc（hdc/ohpm/hvigorw 在 PATH，DEVECO_SDK_HOME 已设）
- **官方 DevEco CLI**：`@deveco/deveco-cli`@1.2.2 已通过 npm 全局安装（~/.npm-global/bin，已入 PATH），封装 build/run/device/emulator/auth/signature/log 全套；识别真机"HUAWEI Pura X Max 典藏版"；`devecocli auth status`=未登录（构建/签名前需 `devecocli auth login`，需用户配合扫码/登录华为账号）
- SDK：HarmonyOS 6.1.1 (API 24)，arm64
- 真机：Pura X Max = HOP-AL10，HarmonyOS 7.0.0，arm64-v8a，hdc 已识别（序列号 6HR0226409033051）
- 华为开发者账号：已有

## 关键决策（待 grill 确认）
- [x] 目标鸿蒙版本：HarmonyOS NEXT 纯鸿蒙（API 12+），不兼容安卓（已确认 2026-08-11）
- [x] 设备形态：Pura X Max（阔折叠），"像素级"指功能完整复刻非逐像素布局；展开态用左侧栏原版布局，折叠态紧凑适配（已确认 2026-08-11）
- [x] 代理核心：mihomo(Clash Meta) 交叉编译为鸿蒙 native 库，前端经 RESTful API 通信，与原版架构同构（已确认 2026-08-11）
- [x] 复刻范围：三期全做——M1核心可用(profiles/proxies/home/settings基础) → M2完整对齐(connections/rules/logs/settings全量/配置编辑) → M3锦上添花(unlock流媒体检测/主题/卡片)，最终全功能对齐（已确认 2026-08-11）
- [x] 走系统 VPN：VpnExtensionAbility 为目标 + 系统代理降级；用户有/愿注册华为开发者账号（已确认 2026-08-11）；政策风险：VPN 受限权限审核
- [x] 前端技术栈：纯 ArkTS + ArkUI 重写，组件结构对照 Clash Verge React 组件树翻译，状态管理 @State/@Provide，数据层直连 mihomo RESTful API（已确认 2026-08-11）
- [x] 项目命名：hmos-openvpn；仓库 ~/harmony-vpn（Git main 分支，2026-08-11 建立），app/ 放鸿蒙工程，docs/ 放文档，研究源码在 ~/harmony-vpn-research/clash-verge-rev
- [x] 上架目标：仅自用侧载（自有开发者账号签名装 Pura X Max），代码开源备选；不上 AppGallery（已确认 2026-08-11）
- [x] 多语言：中英双语，i18n 框架预留可扩展（已确认 2026-08-11）
- [x] 主题：M1 支持亮/暗/跟随系统三档，色值用原版提取值；主题色自定义放 M3（已确认 2026-08-11）
- [x] 开发节奏：自主推进、里程碑验收，仅在需用户操作的节点打扰；全程 Pura X Max 真机调试（HDC USB/无线）；华为开发者账号已有或愿注册（已确认 2026-08-11）

## 状态
- Grill 阶段完成（10/10 决策全部确认）。
- 设计评审：R1 完成（v0.1→v0.2，4阻断+8重要）；R2 完成（v0.2→v0.3，1阻断[运行态动态语义/Go runtime不可重启/配置变更分级L1-L4]+全部重要[接口契约/错误码/反馈回路/状态归属/演进债务/安全模型/性能预算]）；R3 终审（重构保真+实施就绪）进行中。
- **起步路径已拍板（2026-08-11）：复用 ClashBox proxy_core 模块（Apache-2.0，独立库模块），UI 从零用 ArkTS 搭**。
- 官方 DevEco CLI @1.2.2 已装并识别真机；devecocli auth 未登录（构建前需用户配合登录）。
- 待办：R3终审、CONTEXT.md/ADR、M0开工（权限矩阵+工程骨架+烟囱测试）。
- go-ohos 工具链调研完成（docs/go-ohos-toolchain-research.md）：官方 Gitee ohos_golang_go 已归档(Go1.22太老)；生产用 **yourblacksky/ohos_golang_go（Go 1.25.12，release-branch.go1.25）**，无预编译包须源码编译(GOTOOLCHAIN=local ./make.bash)；-tags "ohos with_gvisor" + -tlsmodegd(ARM64 TLS)；gvisor-ohos=MetaCubeX/gvisor 鸿蒙适配分支(随ClashBox子模块)；ohos-napi go mod 直拉。印证"优先复用现成.so，自建工具链仅复现/备选"决策正确。
