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
- 设计评审：R1（4阻断+8重要）→ R2（1阻断+全部重要）→ R3 终审（2阻断+9重要强前置）全部闭环，**设计定稿 v0.3.1（docs/design-v0.3.1.md），可进入 M0**。ADR-0001 复用proxy_core、ADR-0002 单进程NAPI直连 已入库（docs/adr/）。
- **M0a 全部完成（2026-08-11）**：①权限矩阵文档（docs/m0a-1-permission-matrix.md，无需 MANAGE_VPN）②工程骨架（app/，proxy_core 集成，BUILD SUCCESSFUL）③签名+真机安装成功（用户用 DevEco IDE 自动签名生成 default_app_*.cer/p12/p7b，绑 com.hmos.openvpn + 真机 UDID；entry-default-signed.hap 已装真机并启动，进程存活）
- **起步路径已拍板（2026-08-11）：复用 ClashBox proxy_core 模块（Apache-2.0，独立库模块），UI 从零用 ArkTS 搭**。
- 官方 DevEco CLI @1.2.2 已装并识别真机；**devecocli auth 已登录（Jas****，2026-08-11），但 signature generate 报"未实名"被华为云端签名服务拒绝**。
- **签名正确路径（关键发现 2026-08-11）**：DevEco Studio IDE 的自动签名（File→Project Structure→Signing Configs→Automatically generate signature）不需要 CLI 实名——chat-1 工程（~/Documents/Qoder/2026-08-11/chat-1，bundle=com.hermes.remote）今天 02:39 用 IDE 自动签名成功，签名材料在 ~/.ohos/config/default_chat-1_*.cer/p12/p7b，绑本机真机 UDID（445EFF...），已实测安装成功。**我们的工程签名需用户在 IDE 里对 ~/harmony-vpn/app 做同样操作**。
- 纯本地自签（hap-sign-tool 自建 CA）**不可行**：工具强制信任链到华为官方根，generate-app-cert 报 Param is not trusted；sign.sh 方案已废弃。
- 待办：M0开工（权限矩阵实测[需用户登录devecocli签名]+工程骨架+烟囱测试）；实施任务清单展开后再过一轮语义一致性审查。
- go-ohos 工具链调研完成（docs/go-ohos-toolchain-research.md）：官方 Gitee ohos_golang_go 已归档(Go1.22太老)；生产用 **yourblacksky/ohos_golang_go（Go 1.25.12，release-branch.go1.25）**，无预编译包须源码编译(GOTOOLCHAIN=local ./make.bash)；-tags "ohos with_gvisor" + -tlsmodegd(ARM64 TLS)；gvisor-ohos=MetaCubeX/gvisor 鸿蒙适配分支(随ClashBox子模块)；ohos-napi go mod 直拉。
- **M0b-2 结论（2026-08-11）**：①go-ohos 工具链编译成功（yourblacksky/ohos_golang_go Go 1.25.12，make.bash + GOROOT_BOOTSTRAP=~/go-bootstrap/go），hello world c-shared .so 交叉编译验证通过（ARM aarch64 ELF）——**本地独立编译能力已确认**，能力空心化风险对冲成功；②依赖下载需 GOPROXY=https://goproxy.cn,direct（proxy.golang.org 超时）；③-tlsmodegd 是 ClashBox 定制工具链私有 flag，标准 go-ohos 不支持，已移除；④**完整复现 libflclash.so 受阻**：ClashBox 锁定的 core commit 1638edba 已被上游 force-push 删除（GitHub API 确认 No commit found），ohos 分支 HEAD(98ca8a7, 1.10.0) 与 ClashBox 依赖版本(quic-go v0.59.1/metacubex-http 等)类型不匹配编译失败——**记录为已知限制：完整复现需 ClashBox 定制 core，跟随上游节奏；生产继续用现成 libflclash.so（设计文档本来即"优先复用"）**。印证"优先复用现成.so，自建工具链仅复现/备选"决策正确。
- **M1 核心链路真机验收通过（2026-08-12）**：订阅导入→VPN连接→代理分流→出口IP变更 全链路打通。出口IP验证：关VPN=27.38.4.121(深圳联通)，开VPN=102.217.105.28(香港节点PAN-LIAN)。分流正确：国内GeoIP/DomainSuffix直连+国外走节点(日志: match Match using 桔子云[V1-303|香港|x2.0])。
- **M1 真机调试修复的 7 个问题（2026-08-12，纯真机才能发现）**：
  ①HAP安装失败=ohos.permission.NOTIFICATION_CONTROLLER是系统受限权限，普通应用不能申请（安装报 grant request permissions failed code:9568289）→ 移除
  ②导航点击无效=Row+onClick在真机事件失效 → 改用Button承载导航项
  ③订阅导入失败=vailConfig回调契约错误（返回tempPath而非空字符串，Profile.save里非空即throw）→ 回调返回''
  ④VPN核心段错误SIGSEGV(lib_linux.go:92 StartTUN访问currentConfig.General)=VPN进程未加载配置currentConfig=nil → ClashVpnAbility.onCreate里loadActiveConfig()（跨进程状态文件filesDir/active_profile.id + Preferences双读）
  ⑤开关自动关=Toggle.onChange在@StorageLink同步时误触发 → 防抖(toggling标志+500ms)
  ⑥流量全直连=tunIp未设置导致ParseConfig不加IPv4路由0.0.0.0/0 → setTunOptions()走clash_go.sock发SetOptionState(tunIp:172.19.0.1/30, routeAddress:[0.0.0.0/0,::/0])
  ⑦规则不生效=配置路径不匹配（ArkTS写profiles/<id>/config.yaml，Go核心读profiles/<id>.yaml）→ 激活时/启动时同步Go格式配置
- **关键架构事实（M1 验证）**：UI进程与VPN进程(:vpn)共享filesDir（跨进程socket+文件）；clash_go.sock=Go核心IPC；ClashBox.sock=ArkTS LocalSocket；loadConfig等走clash_go.sock直连Go核心；ClashRpcType枚举27项（docs/m1-task-list.md v2已修正）。
- **M2 待开发（2026-08-12）**：connections/rules/logs页面 + settings全量/配置编辑；前置：ClashRpcType已导出（Index.ets加export { ClashRpcType }）。
- **M1+M2 真机验收全部通过（2026-08-12）**：出口IP 220.246.101.59(香港HKT)、YouTube可看、连通性101ms。核心链路：订阅→VPN→分流→节点→出口IP→实际联网 全通。
- **第8个真机修复（2026-08-12，关键）**：节点域名解析环路——proxy-server-nameserver 原为 DoH(https://doh.pub/dns-query)，DoH 的 HTTPS 连接被 TUN 捕获形成环路 → 节点域名解析挂起 → 连接超时（其他设备正常、手机卡死的根因，因为 Mac Clash 有完善 protect 覆盖 DoH，鸿蒙版 protect 未覆盖）。修复：proxy-server-nameserver/default-nameserver 改普通 DNS(223.5.5.5 直连)。
- **M2 完成（2026-08-12）**：Connections连接页(实时列表/断开/清空)、Rules规则页(配置解析)、Logs日志页(实时流/级别过滤)、配置编辑(TextArea对话框)、流量波形图(Canvas蓝下载/绿上传)、节点切换修复(Button承载+清空重建绕过ForEach key不渲染)、测速并发6批+HTTPS测试地址+testing卡死自愈(按钮不enabled禁用防卡死)。
- **ArkUI 真机经验（2026-08-12）**：①Row+onClick在真机事件不可靠，交互元素用Button承载 ②ForEach key变更不触发重渲染，改清空重建(this.groups=[]再加载) ③Button.enabled(false)禁用后onClick不触发，避免用enabled控制防重复(用逻辑自愈代替) ④Scroll包裹内容防卡片溢出。
- **三Agent审查**：M2 一致性审查在跑（proc_aedb25e97671）。
