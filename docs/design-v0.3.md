# hmos-openvpn 设计文档 v0.3

> 版本：v0.3（三Agent R2 架构评审共识修复版）　日期：2026-08-11　作者：Hermes Agent
> 项目：HarmonyOS NEXT 纯鸿蒙 VPN 应用，功能级复刻 Clash Verge Rev（v2.5.3）
> 参照实现：ClashBox（⭐4.2k，github.com/xiaobaigroup/ClashBox，master 分支，已 clone 完整源码）
> 本版变更：落实 R2 评审 1 项阻断（运行态动态语义/Go runtime 不可重启/配置变更分级）+ 全部重要共识（接口契约骨架/反馈回路/状态归属/演进债务/安全模型/测试与性能预算）

---

## 1. 概述

### 1.1 目标
在 HarmonyOS NEXT 上交付一个 VPN 应用，**功能完整对齐 Clash Verge Rev v2.5.3**（"像素级"=功能维度完整，非逐像素布局复刻）。鸿蒙落地的 native 核心**直接复用 ClashBox 的 `proxy_core` 模块**（已验证的 `mihomo→.so→NAPI` 方案），UI 层从零用 ArkTS/ArkUI 搭建、组件结构对照 Clash Verge 的 React 组件树翻译。

### 1.2 非目标
- 不上架 AppGallery（仅自用侧载 + 代码开源备选）
- 不兼容 HarmonyOS 4.x 及更早
- 不逐像素复刻桌面布局（Pura X Max 展开态左侧栏，折叠态紧凑适配）
- 不实现独立 native daemon（鸿蒙沙箱不允许，核心 .so 内嵌于应用进程）
- 不追求桌面端那种"无限期后台常驻"（鸿蒙不允许，见 §6 前台可见性策略）

### 1.3 成功标准
- M1：导入订阅、解析节点、开启系统 VPN、选节点、看流量图，全程真机可用
- M2：connections/rules/logs/settings 全量、配置可编辑
- M3：unlock 流媒体检测、主题色自定义、鸿蒙服务卡片
- 全程在 Pura X Max 真机（HOP-AL10，HarmonyOS 7.0.0）调试验收

---

## 2. 术语表

| 术语 | 定义 |
|---|---|
| **mihomo** | Clash Meta 继任核心（Go），代理协议/规则匹配/TUN/流量；本项目锁 v1.17.1（与 ClashBox 对齐） |
| **proxy_core** | ClashBox 的独立鸿蒙库模块（Apache-2.0），含 mihomo 编译产物 libflclash.so + Go 桥接层 + C++ NAPI 桥 + 权限声明。**本项目直接复用** |
| **libflclash.so** | FlClash 对 mihomo 的封装层编译产物（arm64，约 74MB） |
| **ohos-napi** | OpenHarmony 的 Node-API Go 绑定（likuai2010/ohos-napi v1.0.3），Go 函数以 js.Env/js.Value 暴露给 ArkTS |
| **go-ohos 工具链** | OpenHarmony SIG 的 Go 移植（非官方），GOOS=linux + cgo -buildmode=c-shared -tags "ohos with_gvisor" |
| **gvisor-ohos** | ClashBox 魔改的 gvisor 网络栈（likuai2010/gvisor-ohos，go.mod replace 本地目录），适配鸿蒙 TUN |
| **VpnExtensionAbility** | 鸿蒙系统 VPN 扩展能力（API 11+，@kit.NetworkKit），提供 TUN fd 与生命周期 |
| **TSFN** | NAPI ThreadSafeFunction，Go/native 线程安全回调到 ArkTS UI 线程的机制 |
| **GeoX** | geoip.metadb / geosite.dat 规则数据库文件，mihomo 规则匹配依赖 |
| **配置合成** | 订阅原文 + 用户覆写(merge/script) → 运行时配置 的三层合成管线 |
| **HDC** | 鸿蒙调试桥 |
| **HAP** | HarmonyOS Ability Package，安装包 |

---

## 3. 架构总览

### 3.1 进程模型（关键决策，R1 阻断修复）

**所有组件运行在应用同一进程**（entry 主进程），不启用 `isolationProcess` 隔离。

- `VpnExtensionAbility` 虽是 ExtensionAbility，但默认与 UIAbility **同进程**（除非显式声明隔离，我们不声明）。
- `libflclash.so` 在该进程内 **dlopen 单例加载**，Go runtime 唯一实例。
- UI 侧 NAPI 调用（getProxies 等）与 VPN 侧核心（startTun）**读写同一份内存态**，无跨进程 fd 传递问题。
- TUN fd 由 VpnExtensionAbility.onCreate 在本进程内创建，直接传给同进程的 startTun(fd)，**不跨进程**。

> 依据：ClashBox 实证此模型可行；若误启隔离进程，UI 侧将拿到空核心，数据通路崩塌（R1 MiniMax-A / Kimi-1-2）。

### 3.2 分层架构

```
┌──────────────────────────────────────────────────┐
│ ArkTS UI 层（ArkUI + Navigation）                  │ ← 8页面，对照 Clash Verge 组件树翻译
│ @State/@Provide，中英双语 i18n                      │
├──────────────────────────────────────────────────┤
│ Service 层（ArkTS）                                │ ← 订阅管理/测速/配置合成/流量统计
│ 数据【全部经 NAPI Bridge】，不走 mihomo RESTful      │
├──────────────────────────────────────────────────┤
│ NAPI Bridge（C++，proxy_core/src/main/cpp）        │ ← 类型转换 + TSFN 异步回调
├──────────────────────────────────────────────────┤
│ libflclash.so（Go c-shared，mihomo v1.17.1）      │ ← 协议/规则/TUN/流量/连接
│ 经 ohos-napi 暴露 ~40 函数                          │
├──────────────────────────────────────────────────┤
│ VpnExtensionAbility（同进程）                      │ ← 建 TUN fd → 传 startTun(fd)
│ 后台 dataTransfer 前台可见性策略（见 §6）            │
└──────────────────────────────────────────────────┘
```

### 3.3 数据通路决策：NAPI 直连，禁用 RESTful

**统一决策**：Service 层数据**全部**走 NAPI Bridge 直连 .so 导出函数，**不启用 mihomo external-controller**（不设 9090 端口）。

- 理由：内嵌模式下 RESTful 需 listen 端口，有端口冲突与无鉴权暴露风险；NAPI 直连省一次 IPC、延迟更低。ClashBox 实证。
- 例外：如需调试，可临时起 127.0.0.1 回环 external-controller，**仅回环、不带鉴权对外**。
- 维护成本已知并接受：~40 个函数在 Go 侧包装为 ohos-napi 导出，mihomo 升级时需同步桥接层（因复用 ClashBox proxy_core，跟随其升级节奏）。

### 3.4 关键数据流
- **开启 VPN**：UI → vpnExtension.startVpnExtensionAbility → VpnExtensionAbility.onCreate(同进程)建 TUN fd → NAPI startTun(fd, callback) → mihomo 接管流量
- **数据查询**：ArkTS 经 NAPI 调 getProxies/getTraffic/getConnections 等
- **流式推送**：日志/流量经 TSFN 回调（见 §3.5）
- **配置下发**：配置合成管线产物 → NAPI updateConfig(yamlString) → mihomo 热加载

### 3.5 线程/事件模型（R1 阻断修复）

NAPI 是同步 C API，Go 在 Go 调度器线程，ArkTS 在 UI 线程。跨线程推送统一走 **TSFN（napi_threadsafe_function）**。

| 数据源 | 机制 | 频率/反压 |
|---|---|---|
| 日志 startLog | Go→C++→TSFN→ArkTS 回调 | 缓冲队列，>1000 条/秒丢弃旧日志防 OOM |
| 实时流量 getTraffic | ArkTS 侧 setInterval 轮询 NAPI | 1Hz（流量图足够），页面不可见时停轮询 |
| 总流量 getTotalTraffic | 轮询 | 1Hz |
| 活跃连接 getConnections | 手动刷新 + 页面可见时 2s 轮询 | 连接数大时分页 |
| 节点延迟 asyncTestDelay | 异步 NAPI 回调 | 单组并发测速 |
| 代理状态变更 | TSFN 事件推送 | 即时 |

UI 帧率控制：流量图重绘 ≤1Hz；所有 TSFN 回调先投递到 ArkTS 主线程再 setState。

### 3.5.1 核心状态机（R2 共识）

统一定义 `CoreState` 枚举，所有 TSFN 事件携带此状态，8 个页面渲染统一从此枚举派生（避免"VPN 已关但代理仍可选"的不一致）：

```
CoreState = Idle | Booting | Running | Reloading | Stopping | Error(subCode)
```

### 3.5.2 Go runtime 单进程不可重启约束（R2 阻断修复）

**硬约束**：Go c-shared 库不支持 dlclose 后重新 dlopen（重载必崩）。单进程模型下"重启核心"物理上等于"重启整个应用进程"（隧道必断 + UI 重启）。

**推论**：所有配置变更**必须**在 mihomo 进程内热加载内解决；热加载解决不了的只有进程重启一条路。**文档中任何"重启核心"的隐含假设均不成立**。

**核心级重置的显式流程**（当必须进程重启时）：通知 UI → 断 TUN → 进程退出 → 用户重启应用。

### 3.5.3 配置变更影响分级（R2 阻断修复）

M0 增列 spike「mihomo 热加载边界实测」，产出《配置变更影响分级表》，逐配置字段归级：

| 级别 | 含义 | 例子 | 过渡策略 |
|---|---|---|---|
| L1 | 热加载无感 | 切换节点、规则微调 | UI 无感知，直接生效 |
| L2 | 热加载瞬断 | 部分 listen 变更 | UI toast"应用中" |
| L3 | 需重建 TUN（fd 重传） | TUN 栈切换、DNS 模式、route-address 变更 | UI 显式提示"TUN 重建中，预计断流 N 秒" |
| L4 | 仅进程重启可达 | 少数底层字段 | 走 §3.5.2 核心级重置流程 |

**TUN 重建项清单**（触发时 UI 显式提示断流）：TUN 栈（system/gvisor/mixed）、DNS 模式、route-address、MTU。

### 3.5.4 进程内事件流（R2 共识）

UIAbility ↔ VpnExtensionAbility 虽同进程，但 VPN 侧生命周期事件（onDestroy/系统撤销授权/隧道异常）回传 UI/Service 层的通道选型为 **EventHub**（鸿蒙同进程事件机制，无需 IPC）。数据流补一条：VPN 侧事件 → EventHub → Service 层 → UI。

### 3.6 配置合成管线（R1 重要修复 + R2 并发/事务修复）

三层模型：

```
订阅原文（远程 YAML，原文保留）
   ＋ 用户覆写层（merge 规则 / script 脚本，用户编辑）
   ↓ 合成（导入/更新订阅/编辑覆写 三个时机触发）
运行时配置（合成产物，落盘到应用沙箱 filesDir，供 updateConfig 加载）
```

- **合成时机**：① 新订阅导入 ② 订阅更新 ③ 用户编辑覆写——三者任一发生即重新合成并落盘运行时产物
- **冲突处理**：覆写层优先级高于订阅原文；script 模式由用户脚本全权处理
- **沙箱路径**：mihomo 工作目录（yaml、缓存、GeoX）= 应用 `filesDir`（如 `/data/app/.../files/mihomo/`），由 NAPI initClash 时传入绝对路径
- **并发竞态（R2 共识）**：Service 层加 single-flight + 编辑态标记。检测到"用户编辑覆写未保存"时，订阅自动刷新要么延后（队列化）、要么只更新订阅原文不触发合成，防用户编辑被覆盖丢失。
- **配置变更三步法（R2 共识，原子切换）**：① 本地 YAML 语法 lint（用 mihomo 自带 parser） ② 调 mihomo 校验接口试加载（validate，不切换主配置） ③ 校验通过后原子切换（apply），失败保留上一份配置不变。运行时产物采用"先写 tmp 文件、原子 rename 覆盖"落盘，避免半写状态。**updateConfig 拆为 validateConfig + applyConfig 两段式**。
- **选择记忆迁移（R2）**：切订阅时按"组名→节点名"迁移用户已选节点；同名组/节点不存在时回退到该组首个节点。
- **操作互斥**：updateConfig 进行中的测速/切节点/再次改配置，进入操作队列串行执行，过渡态旧连接默认保活（keep existing, new via new，mihomo 默认行为），UI 提供"关闭所有连接并重连"按钮。

### 3.7 接口契约骨架（R2 共识，先于实现冻结）

**传输格式**：M1 以 JSON string 起步（与 mihomo external-controller 输出格式一致便于调试），大对象（连接表等）统一 JSON string + 分页参数；M2 性能不达标再切 cbor/FlatBuffers（记为已知技术债）。

**统一返回结构**：所有导出函数 Go 侧签名统一 `func() (any, error)`；C++ 侧统一捕获；ArkTS 侧 `Result<T, ClashError>` 包装。

**错误码模型**（8 位分段）：1xxx 参数/调用层、2xxx mihomo 业务层、3xxx 资源/系统层、9xxx panic。Go panic 必须所有导出函数 `defer recover`（**硬性要求**，否则 panic 杀死宿主进程→TUN 死锁→整机断网）。

**TSFN 生命周期契约**：注册/回调/释放三段配对，页面销毁时解绑，进程退出按序清理。

**ABI 版本握手**：Bridge 加零参 `nativeVersion(): { core, abi, buildCommit }`，App 启动校验与 manifest 预期版本一致；ClashBox 升级时强制 bump abi 字符串；直接用的上游 .so 加 sha256 锚定 + 烟囱测试自检。

**4 个关键函数完整 TS 类型**（M0 固化，其余 36 个列源码定位）：getProxies（嵌套结构体）、getTraffic（up/down 标量）、updateConfig/applyConfig（带错误码 Result）、startLog（带退订语义 callback）。

### 3.8 状态归属与持久化（R2 共识）

| 数据类别 | 存储 | 说明 |
|---|---|---|
| 用户偏好（主题/语言/端口/最近选中节点/模式） | Preferences KV（@kit.ArkData） | 轻量，UI 改写 |
| 订阅元数据/历史/备份 | RDB 关系型（@kit.ArkData） | 结构化 |
| 运行时配置产物 | filesDir 文件 | **只能由配置合成管线产出**，UI 不直接改 |
| GeoX 数据 | filesDir + assets 内置 | |

**状态唯一来源表**（M0 交付物）：逐设置项标注【存储位置｜合成层归属｜生效路径｜运行中可改性】。配置类操作统一"乐观 UI + 核心事件回执，失败回滚"。跨页面全局状态用轻量 EventBus（不引第三方库），页面级用 @State。

### 3.9 反馈回路：核心事件清单（R2 共识）

所有核心事件走既有 TSFN 机制（不新增通道），携带 CoreState：

```
ConfigApplied / ConfigFailed(errorCode,msg) / CoreExit / TunnelStateChanged / ProxyChanged / Log(level,payload)
```

**配置 reload 闭环**：updateConfig 改为异步返回 Promise，同时 TSFN 推送 ConfigApplied/ConfigFailed；UI 据此显示 toast 或"重新加载中"态。
**核心健康**：heartbeat / CoreExit 事件 + UI 状态降级逻辑，防"VPN 已连接"长期说谎。

---

## 4. 功能模块（对照 Clash Verge 八页面 + mihomo 核心特性）

| 页面/特性 | 鸿蒙实现要点 | 里程碑 |
|---|---|---|
| profiles 订阅 | 增删改/远程更新/导入(URL/文件/二维码)/拖拽排序；**订阅流量信息(subscription-userinfo)展示**；YAML编辑/合并脚本(M2)；**配置备份/导入导出(M2)** | M1核心+M2高级 |
| proxies 代理 | 代理组树/延迟测速/切换 | M1 |
| home 首页 | 流量图/当前代理/模式切换/**IP信息(自请求第三方,走代理可开关)**/系统信息 | M1 |
| connections 连接 | 活跃连接表格/排序/关闭单个/关闭全部 | M2 |
| rules 规则 | 规则列表 | M2 |
| logs 日志 | startLog 流式/级别过滤/搜索 | M2 |
| settings 设置 | 端口/模式/主题/语言/VPN开关/DNS配置/TUN栈选择 | M1基础+M2全量 |
| unlock 解锁 | 流媒体检测逐节点（M3 前先 spike 验证核心侧 dialer 能力） | M3 |
| **GeoX 数据** | geoip.metadb/geosite.dat：assets 内置 + 应用内更新（updateGeoData） | M1 |
| **DNS 配置** | fake-ip/redir-host/nameserver 设置 | M1 |
| **TUN 栈选择** | system/gvisor/mixed 可选（解释为何需 gvisor-ohos） | M1 |
| **规则/代理提供者** | rule-providers / proxy-providers 支持（订阅兼容性） | M2 |
| **订阅自动刷新** | 定时更新订阅 | M2 |
| **节点分享** | 二维码导出（与导入对称） | M2 |
| **VPN 断连重连 + fd 清理** | 系统回收后重建 TUN，防 fd 泄漏致整机断网 | M1 |
| **i18n 落地** | M1 结束时所有用户可见字符串入 string.json（zh/en 双套） | M1 |

鸿蒙特有：VpnExtensionAbility 服务、前台可见性策略、服务卡片(M3)、折叠屏双态布局(展开态 M1 / 折叠态降级 M2)。

---

## 5. 里程碑

### M0 工程奠基（先行，含 4 个 R1 阻断前置）

**M0a 权限与空壳（先于工具链，最高优先）**
1. **MANAGE_VPN 权限矩阵确认**（🔴 R1 共识，M0 第一交付物）：实测 VpnExtensionAbility 所需权限清单（MANAGE_VPN/INTERNET/KEEP_BACKGROUND_RUNNING/dataTransfer），确认自用侧载下受限权限的获取路径（调试 profile 声明），输出书面权限矩阵文档 + hdc 实测清单
2. 鸿蒙工程骨架（entry + 引入 proxy_core 模块）
3. 真机签名跑通空 HAP

**M0b 核心链路烟囱测试**
4. 引入 ClashBox proxy_core（含现成 libflclash.so 优先复用，go-ohos 自建编译为备选/复现路径）
5. NAPI Bridge 调通
6. **烟囱测试（M0 退出门，R1 共识升级）**：真机弹出系统 VPN 授权框 → VpnExtensionAbility.onCreate 建 TUN fd → startTun(fd) 返回成功 → mihomo 启动 5 秒 → 主动 stop → 进程不崩、无 panic、fd 正确清理

- **M0 退出门**：① 权限矩阵文档 ② 真机装空壳 ③ 烟囱测试全绿（VPN 授权弹窗+隧道创建+核心起停+资源清理）
- **go-ohos fallback**：若现成 .so 不可用且自建工具链 M0 第 5 天跑不通，切备选方案（纯 C tun2socks + Go 仅协议层，体积降至 ~10MB）

### M1 核心可用
- profiles：导入(URL)/更新/切换订阅、节点列表、订阅流量信息展示
- proxies：代理组树 + 延迟测速 + 切换
- home：VPN 开关 + 模式切换 + 实时流量图 + IP 信息
- settings 基础：主题三档、语言、端口、DNS、TUN 栈
- GeoX 数据内置 + 更新
- VPN 断连重连与 fd 资源清理
- i18n 全部字符串入 string.json（zh/en）
- **M1 退出门**（可复现，替代"YouTube通"）：固定测试订阅（≥3 节点）下，经代理 curl 目标返回 200 且延迟低于阈值，流量图 Rx/Tx 非零；VPN 切后台 30 分钟连接存活率实测记录

### M2 完整对齐
- connections/rules/logs 三页全量
- profiles 高级：YAML 编辑、二维码导入导出、合并/脚本、备份/导入导出
- 规则/代理提供者、订阅自动刷新
- settings 全量、折叠态降级布局
- **M2 退出门**：对照「Clash Verge v2.5.3 功能基线清单」逐项打勾（该清单为 M0 交付物，见 §8），除 M3 项外全绿

### M3 锦上添花
- unlock 流媒体检测（M2 末期先 spike 验证）
- 主题色自定义
- 鸿蒙服务卡片
- **M3 退出门**：全功能对齐

---

## 6. 前台可见性策略（原"保活"重写，R1 共识）

鸿蒙不允许应用无限期后台常驻（`dataTransfer` 长时任务有上限，VpnExtensionAbility 由系统托管生命周期）。明确语义：

- **放弃桌面端 daemon 常驻语义**。应用切后台后允许系统回收。
- 策略：申请 `KEEP_BACKGROUND_RUNNING` + `dataTransfer` 长时任务尽量延长存活；VPN 隧道由系统 VpnExtensionAbility 托管，应用进程被杀后隧道状态由系统决定。
- 接受"回收后由用户重新点击启动"的语义，不追求 Clash 桌面端那种常驻。
- M1 实测灭屏 30 分钟连接存活率后定最终策略。

---

## 7. 风险登记册

| 风险 | 等级 | 缓解 |
|---|---|---|
| MANAGE_VPN 等受限权限拿不到 | 🔴 高（R1 升级，一票否决项） | M0a 第一任务实测确认；自用侧载走调试 profile 声明路径 |
| go-ohos 工具链非官方、Go runtime 稳定性未知 | 🔴 高 | 优先复用 proxy_core 现成 .so；自建仅复现；fallback tun2socks；M0 烟囱测试验证 |
| VpnConfig.routes 在 API 23 前不生效 | 🟡 中 | 目标 API 23+，SDK 6.1.1(24)/真机 7.0.0，规避 |
| 后台被系统杀 | 🟡 中 | §6 前台可见性策略，接受回收语义 |
| mihomo 升级桥接层维护成本 | 🟡 中 | 复用 proxy_core 跟随 ClashBox 升级；锁 v1.17.1 保交付期稳定，定义升级触发条件 |
| GeoX 数据缺失致规则失效 | 🟡 中 | M1 assets 内置 + 应用内更新 |
| 74MB 包体积/常驻内存 | 🟢 低 | 自用可接受；M0 测 hdc ps RSS |
| 折叠屏双态适配工作量 | 🟢 低 | 展开态优先，折叠态 ArkUI 响应式降级 |
| 单设备(Pura X Max)依赖 | 🟢 低 | M2 加一轮次要设备烟雾测试 |
| ClashBox 上游停滞/弃坑/许可变更 | 🟡 中（R2 新增） | ① M0 必交付"本地独立 build .so 能力"（go-ohos 复现验证，非可选）② 上游半年无 commit 触发 fork 评估 ③ fallback tun2socks 保持可复现（保底非降级） |
| fork/打补丁无决策机制 | 🟡 中（R2 新增） | patch SLA：上游 14 天无响应则本地建 patch 分支；维护"侵入式修改清单"形成差异补丁包便于 rebase |
| 能力空心化（丧失改 Go 层能力） | 🟡 中（R2 新增） | go-ohos 复现出功能等价 .so 从"第5天放弃"改为 M0–M1 必做一次的验证性目标；确要放弃则书面登记"fork 无源可编"债务并立 fork 预案 |
| HarmonyOS NEXT 大版本升级兼容性 | 🟡 中（R2 新增） | minSdk=API 11（VpnExtensionAbility 起点）、targetSdk=跟随 HOS NEXT GA；每年大版本发布后 30 天内回归跑 M0 烟囱测试 |
| 恶意订阅/配置安全风险 | 🟡 中（R2 新增） | 见 §11 安全模型 |

**核心版本策略**：交付期内锁 mihomo v1.17.1 保稳定；升级触发条件=协议不兼容（reality/hysteria2 演进）或安全修复，软触发=距上次升级超 12 个月；升级需重跑 M0 烟囱测试 + M1 退出门。

---

## 7.1 安全模型（R2 共识）

VPN 应用是高价值目标，必须覆盖：
- **订阅 URL**：强制 HTTPS + 证书校验，防 SSRF；拒绝 file:// 等危险 scheme
- **YAML 解析**：限制锚点/别名深度，防 billion laughs 炸弹
- **script 模式**（用户脚本=任意代码执行）：需用户显式二次确认开关，默认关闭
- **IP 自请求**：默认直连第三方（不走代理，防信息泄露与鸡生蛋），走代理测连通性需用户显式开启且用 ephemeral 测试连接
- **凭据**：应用禁止明文存储任何 token/订阅密钥，走系统安全存储
- **DNS 泄漏**：fake-ip 模式下确保 DNS 走核心，不泄漏到本地运营商

---

## 7.2 测试策略与性能预算（R2 共识）

**测试分层**：
- M0：沉淀 Mock NAPI（让 Service 层可独立单测）+ 契约测试 golden 文件
- M1：引入真机自动化（hdc 驱动）；proxy_core 升级时跑 M1 退出门作为回归套件
- M2 退出门的功能基线清单打勾辅以自动化，避免纯人工回归

**性能预算**（附测量方法）：
| 指标 | 目标 | 测量 |
|---|---|---|
| App 冷启动 | < 3s | hdc 打点 |
| 内存常驻 RSS（含 74MB .so） | < 200MB | hdc shell ps |
| 流量图采样延迟 | 1Hz 足够 | 帧率统计 |
| 节点切换生效 P99 | < 500ms | 自定义打点 |
| TUN 重建断流时长 | < 3s | 实测 |

**可观测性**：M1 退出门含"现场日志一键导出"（hdc log 抓取 + 应用内诊断导出）。

---

## 8. 开放项与交付物

**已闭合（R1 拍板）**：
- ~~起步路径~~ → **复用 ClashBox proxy_core（Apache-2.0），UI 从零搭**（用户已拍板 2026-08-11）
- ~~go-ohos 获取方式~~ → 优先用现成 .so，自建为备选（子Agent调研中，非关键路径）

**M0 必须交付的工件**：
1. **权限矩阵文档** + hdc 实测清单（🔴 第一优先）
2. **Clash Verge v2.5.3 功能基线清单**（逐项标 对齐/鸿蒙改编/不对齐+理由，作为 M2 验收基线）
3. go-ohos 锚定表（repo/commit/版本/已知 issue）+ fallback 触发条件 + **本地独立 build .so 复现验证**
4. NAPI ~40 函数接口面清单（指向 ClashBox proxy_core 源码文件）+ **4 个关键函数完整 TS 类型 + 错误码模型**
5. M0 子任务依赖图（go-ohos→NAPI桥→VpnExtensionAbility空壳→烟囱测试）
6. **配置变更影响分级表**（mihomo 热加载边界 spike 产出，L1–L4）
7. **状态唯一来源表**（逐设置项存储/合成层归属/生效路径/运行中可改性）
8. **Mock NAPI + 契约测试 golden 文件**（让 Service 层可独立单测）

---

## 9. 审查追溯

| 轮次 | 日期 | 报告 | 采纳要点 |
|---|---|---|---|
| R1 细节正确性 | 2026-08-11 | /tmp/hmosvpn-r1-verify-{glm,kimi,minimax}.md | 4 阻断（进程模型/线程模型/M0烟囱测试/权限前置）+ 8 重要全部采纳；RESTful 表述统一为 NAPI 直连；补配置合成管线/GeoX/前台可见性策略/功能基线清单；起步路径用户拍板复用 proxy_core |
| R2 架构聚焦 | 2026-08-11 | /tmp/hmosvpn-r2-verify-{glm,kimi,minimax}.md | 1 阻断（运行态动态语义：Go runtime 单进程不可重启约束/配置变更影响分级 L1-L4/updateConfig 拆 validate+apply 两段）+ 全部重要（接口契约骨架/错误码模型/Go panic recover 硬性要求/核心状态机/反馈回路核心事件清单/状态归属与持久化/演进债务 fork 策略+能力空心化/安全模型/测试策略+性能预算）；进程内事件流选型 EventHub；订阅并发 single-flight；选择记忆迁移 |

---

## 10. 验证请求（R3：重构保真 + 实施就绪审查）

请三位审查者在 v0.3 基础上做**终审**，**不要重复 R1/R2 已解决并写入本文档的问题**。聚焦：
1. **重构保真**：v0.2→v0.3 新增的运行态语义/接口契约/状态归属/安全模型等，是否丢失或改歧义了 R1/R2 已修复的机制；新增章节与原有章节（§3 架构/§5 里程碑/§7 风险）是否一致无矛盾
2. **实施就绪**：本文档能否直接指导 M0 开工——权限矩阵怎么实测、烟囱测试怎么跑、接口契约怎么固化，是否都有可执行的依据
3. **跨章节一致性**：CoreState 枚举、核心事件清单、配置变更三步法、错误码模型在 §3 各处引用是否统一
不要质疑已锁定的产品决策。若无阻断问题请明确给出"可进入 M0"结论。
