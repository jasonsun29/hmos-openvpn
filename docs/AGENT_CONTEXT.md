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
- **P3 第一批完成（2026-08-14，devecocli/hvigorw 全程验证）**：
  - 前置修复（checklist 第 1 步发现的存量问题，均为 P2 未提交改动引入）：
    ①`AppScope/app.json5` 顶层 `privacy` 块当前 SDK（API 24）schema 不支持（顶层只允许 `app`）→ 迁到 docs/privacy-statement.md，构建恢复
    ②P1-8 签名占位符方案不可行：hvigor/CLI 不解析 local.properties 的 `${signing.dir}/${signing.cert.name}`（实测 Invalid storeFile）→ build-profile.json5 恢复硬编码绝对路径
    ③26 个 ArkTS 编译错误清零：fileUtils 拆分后 getHome 迁移到 appPath（ActivationStore/ClashVpnAbility/DiagnosticCollector/GeoDataInstaller 的 import 修正）、CoreLogger（openSync 返回 File 取 .fd + levelToString 静态化 + 删命名空间当值用）、Rules（stats 改 string|Resource）、SettingsRepository（去 as any）、SocketStubService（解构改 Map.values()）、ClashVpnAbility（patch 强类型 + as DnsEnhancedMode/TunStack）
  - 第一批 5 项全部完成：t32 formatBytes 公共化（删 Home/Connections/Profiles 3 处重复，统一 AppService.formatBytes）→ t30 Canvas onAreaChange 自适应 → t31 波形批量裁剪（MAX_HISTORY_POINTS=60，2 倍阈值 splice）→ t34 AsyncUtils.tryRunAsync（新建 utils/AsyncUtils.ets，Home 三处高频 catch 已迁移）→ t35 Connections 搜索/过滤（searchText + filtered() + 空态区分）
  - 验证：devecocli build（debug）通过，entry-default-signed.hap 产出；proxy_core 本地单测 1/1 通过；CodeLinter 0 error（Home 循环读状态变量警告已顺手修复，ClashVpnAbility await-thenable / Proxies L101 为存量 warning）
  - 待办：①21 个真机单测（ohosTest）需连 Pura X Max 后 `hvigorw test` 跑 proxy_core 模块 ②devecocli check compat 需 DevEco Studio ≥26.0.0.810（本机 6.1.1.300 不支持；已评估：26.0.0 目前是 Beta，升级会动 API 24 SDK/go-ohos/签名链路，用户拍板暂不升级）③P3 第三~四批未开始
- **P3 第二批完成（2026-08-14）**：t36 本地文件导入（DocumentViewPicker.select + Profile.saveByUri，文件名校验去扩展名做订阅名）→ t40 订阅导出（picker.save newFileNames + fileIo.copyFile）→ t37 Settings GeoX 数据卡片（mtime 显示上次更新 + 一键更新）。**关键修复：updateGeoData 参数顺序**——Go IPC（ipc.go UpdateGeoData case）约定 Params[0]=geoType(MMDB/ASN/GeoIp/GeoSite)、Params[1]=geoName(文件名，Path.Resolve 拼核心工作目录)，原 ArkTS 签名 (geoName, geoType) 名字反且发送反序，会导致 Go switch 无匹配、RPC 挂到超时；已修正 SocketProxyService.updateGeoData(geoType, geoName) 并同步 Settings 调用。构建通过、CodeLinter 0 error（顺手清掉 Home.refreshIpInfo 循环内写状态的 warning 与 ClashVpnAbility await-thenable；Proxies.ets L101 循环内渐进刷新为有意保留）
- **P3 真机验证（2026-08-14，Pura X Max 全程 HDC+devecocli ui 驱动）**：
  - 单测：21 个 ohosTest 用例聚合进本地测试入口（src/test/List.test.ets import 4 个套件）宿主机跑通 **23/23**。修复真 bug：TrafficValue 单位换算边界 `>` → `>=`（1024 落 B、1024² 落 KB）、Settings mtime 秒/毫秒混淆（显示"20658 天前"）。ohosTest 设备测试管线在 DevEco 6.1.1 对 HAR 模块有缺陷（模板生成路径/`unit.test.replace.page` 注入/sourceMaps.map ENOENT 三关），已用 scripts/fix-ohosTest-harness.sh + src/ohosTest/resources/base/profile/main_pages.json + src/main/resources/base/profile/main_pages.json 修复前两关，第三关为 hvigor 缺陷放弃，本地聚合替代
  - 测速：Proxies 并发 6→16（真机大订阅 ~1000 节点全量 11min→3.5min）；"测速中..."自愈、节点切换、延迟回显均正常
  - GeoX：卡片+时间显示正常；更新 RPC 全链路通（参数顺序修复生效，Go updater 执行下载）；**下载受订阅质量阻塞**——桔子云订阅节点实际流量不可用（健康检查 47/106ms 的节点真实拨号 relay i/o timeout / REALITY 握手失败），且 GitHub/jsdelivr/fastly 均命中 MATCH 兜底规则走代理；CN 主机直连正常（myip.ipip.net 出口 27.38.4.121 验证）。已将 geox-url 默认值从 GitHub 改为 cdn.jsdelivr.net 镜像（直连友好）+ updateGeoData socket 超时 120s；订阅恢复健康节点后即可成功
  - 导入/导出：picker 打开/导航/文件名（"桔子云.yaml"）正常；导出全流程成功（文件已落 Download，同名冲突对话框验证）；导入 picker 看不到刚导出的文件=Media Library 索引延迟（保存 picker 无过滤同样看不到，非 fileSuffixFilters 问题）
  - 心跳：VPN 进程被系统杀后 UI 正确提示"VPN服务被系统干掉了"（P0-4 生效）
  - 工具资产：hdc uitest uiInput keyEvent 2=返回；devecocli ui layout/click/swipe/fling/text 可用；hilog 缓冲会被大流量日志快速轮转；**hdc file recv 可读应用沙箱**（拉取 yaml 验证用）
- **P3 全局模式/节点持久化（2026-08-14，实验性，用户判断 yaml 补丁方法存疑，明日重新评估）**：
  - 已完成并真机验证：模式切换真实生效（核心日志 using GLOBAL 证据）；SelectedMapStore 跨进程持久化（mode + 各组节点选择，VPN 重启恢复）；Proxies 模式感知查询；Home setMode GLOBAL 继承当前节点；大小写归一（按钮小写 vs 枚举大写，曾导致继承分支与 ParseProxyGroup 失效）
  - **存疑部分（明日重做方向）**：YamlGlobalPatch——无 Go 重编译约束下，在 Go 格式 yaml 同步时给 GLOBAL 组补全成员（DIRECT/REJECT+组名+节点名）。已发现并修复两个大坑：①TextEncoder 池化 ArrayBuffer 尾部陈旧字节被写盘（53 行平移副本+坏规则 MATCH,桔子云.in-addr.arpa，核心报 rules[5383] error——已修 fileUtils.writeFile 及全部写盘点，按视图 byteLength 截断+TRUNC）②插入块缩进风格与原文件混排导致 yaml 非法（mihomo 宽容解析吞掉成员）——已重写为缩进自适应+独立 dash 风格，**最新版尚未真机验证**
  - 设备当前状态：device yaml 为缩进混排版本（mihomo 宽容解析通过、核心可跑）；明日应从干净 config.yaml 重新同步验证
  - 明日待办：①评估 yaml 补丁方案或换路线（重编译 Go / 接受机场现状等）②干净 config.yaml 重同步 + 验证 GLOBAL 成员 ③继续第四批（t33/t43/t44）
- **M3 锦上添花 + M2 遗漏补齐完成（2026-08-15，提交 5680744）**：
  - 主题色自定义（预设 10 色板 + 修复主题应用机制：原 getColors 无调用方、colors 恒浅色；现在 MainPage.applyTheme 按模式×自定义色解析，themeChanged 广播即时生效）
  - 订阅二维码分享（Profiles「二维码」按钮 → clash://install?url= 二维码，与 t41 扫码导入闭环）
  - unlock 流媒体检测页（第 8 页，10 服务；UI 进程 http 经 VPN 出口检测；核心逐节点×逐服务检测留作 spike：healthCheck 仅支持单一 test-url）
  - 鸿蒙服务卡片 v1（VpnCardFormAbility，2*2/2*4，VPN 状态+模式，点击打开应用；SelectedMapStore 增 vpnOn 状态；form_config uiSyntax=arkts 是构建必需字段）
  - 折叠态降级布局（宽 <640vp 侧栏降级 64vp 图标栏）
  - 构建通过、lint 0 error、单测 30/30；**全部真机验收待设备连接**
- **P3 重构（2026-08-15，按用户三点要求重做，替代 yaml 补丁方案）**：
  - 用户需求：①选端点不能依赖 VPN 在线 ②默认全局模式 ③全局端点与订阅结构无关（直连=不走代理、其他=全走所选端点）
  - 新架构（YamlGlobalPatch 已删除）：
    - `ConfigReader`（proxy_core）：离线解析本地 config.yaml → 组/节点视图（选端点不再依赖 VPN）
    - `GlobalModeResolver`：应用侧状态（持久化模式+选择）→ 核心参数映射——DIRECT→mode=Direct；组→mode=Global+GLOBAL→组；节点→mode=Global+GLOBAL→所在组+组→节点；未选/失效→Global 默认；rule→Rule（组内选择保留）
    - `AppService.applyGlobalEndpoint/patchMode`：在线即时应用（changeProxy 用真实组名，绕开核心 Set 校验）
    - Proxies 页双源：离线可浏览/选择（"已记录，开启 VPN 后生效"+在线状态横幅），在线叠加 RPC 延迟；全局模式=单组平铺端点列表（直连+全部组+全部节点）
    - Home：默认全局、模式持久化、当前代理优先显示持久化端点；VPN 启动（ClashVpnAbility）用解析器恢复模式+selected-map；ClashConfig.mode 默认 Global
  - 验证状态：构建通过、30/30 单测（ConfigReader+Resolver 6 个新用例）、CodeLinter 0 error；**真机验证待设备连接**（清单：VPN 关闭时 Proxies 离线可看可选 → 选端点 → 开 VPN → 核心 using GLOBAL+映射生效 → 重启 VPN 状态保留）

- **P3 第三批完成（2026-08-14，构建+lint+真机验证）**：
  - t38 updateDns：**弃用**。查清契约（Go 读 args[0] 为逗号分隔字符串、OHOS 侧只改核心自身 systemResolver 不触碰系统 DNS、TUN 重建窗口有全断网风险、fake-ip 已工作正常），在 libflclash/Index.d.ts 补声明+完整决策记录（接入点留档）
  - t39 UI 进程轻量保活：状态恢复方案——EntryAbility.onBackground/onForeground/onNewWant 调 pingCoreNow()，MainPage.aboutToAppear 在 vpnOn=true 时立即验活（心跳结果驱动 vpnAlive/vpnOn 复位，不复用长时任务）
  - t41 扫码导入：ScanKit（@kit.ScanKit scanBarcode.startScanForResult + ScanType.QR_CODE），doImportUrl 公共化（URL/扫码共用），clash://install?url= schema 解析，CAMERA 权限（module.json5 + camera_reason 三语 + requestPermissionsFromUser）。真机验证：扫码按钮 → 权限申请 → 系统扫码页正常拉起（含图库备选入口）；真实扫码需物理指向二维码
  - t42 EntryBackupAbility：onBackup/onRestore 显式拷贝 RDB(fsclash.db+wal/shm)/active_profile.id/profiles 目录（copyFileSync+copyDir），backup_config.json includes/excludes 白名单。系统备份触发需端云备份场景，编译+注册验证通过
  - 构建通过、CodeLinter 0 error


  - 工具资产：devecocli skills add 装了 3 个官方 skill 到 app/.claude/skills/（hmos-arkts-syntax-checker / hmos-arkts-knowledge-retriever / hmos-arkui-knowledge-retriever，含本地 linter-cli 与 docs 检索脚本），`devecocli docs search` 可查官方文档
