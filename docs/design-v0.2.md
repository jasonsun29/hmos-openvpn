# hmos-openvpn 设计文档 v0.2

> 版本：v0.2（三Agent R1 评审共识修复版）　日期：2026-08-11　作者：Hermes Agent
> 项目：HarmonyOS NEXT 纯鸿蒙 VPN 应用，功能级复刻 Clash Verge Rev（v2.5.3）
> 参照实现：ClashBox（⭐4.2k，github.com/xiaobaigroup/ClashBox，master 分支，已 clone 完整源码）
> 本版变更：落实 R1 评审 4 项阻断 + 8 项重要共识；起步路径已由用户拍板（复用 proxy_core，UI 从零搭）

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

### 3.6 配置合成管线（R1 重要修复）

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

**核心版本策略**：交付期内锁 mihomo v1.17.1 保稳定；升级触发条件=协议不兼容（reality/hysteria2 演进）或安全修复；升级需重跑 M0 烟囱测试 + M1 退出门。

---

## 8. 开放项与交付物

**已闭合（R1 拍板）**：
- ~~起步路径~~ → **复用 ClashBox proxy_core（Apache-2.0），UI 从零搭**（用户已拍板 2026-08-11）
- ~~go-ohos 获取方式~~ → 优先用现成 .so，自建为备选（子Agent调研中，非关键路径）

**M0 必须交付的工件**：
1. **权限矩阵文档** + hdc 实测清单（🔴 第一优先）
2. **Clash Verge v2.5.3 功能基线清单**（逐项标 对齐/鸿蒙改编/不对齐+理由，作为 M2 验收基线）
3. go-ohos 锚定表（repo/commit/版本/已知 issue）+ fallback 触发条件
4. NAPI ~40 函数接口面清单（指向 ClashBox proxy_core 源码文件）
5. M0 子任务依赖图（go-ohos→NAPI桥→VpnExtensionAbility空壳→烟囱测试）

---

## 9. 审查追溯

| 轮次 | 日期 | 报告 | 采纳要点 |
|---|---|---|---|
| R1 细节正确性 | 2026-08-11 | /tmp/hmosvpn-r1-verify-{glm,kimi,minimax}.md | 4 阻断（进程模型/线程模型/M0烟囱测试/权限前置）+ 8 重要全部采纳；RESTful 表述统一为 NAPI 直连；补配置合成管线/GeoX/前台可见性策略/功能基线清单；起步路径用户拍板复用 proxy_core |

---

## 10. 验证请求（R2：架构聚焦审查）

请三位审查者在 v0.2 基础上做**架构层完备性**审查，**不要重复 R1 已解决并已写入本文档的问题**（进程模型、线程/事件模型、M0 烟囱测试、权限前置、RESTful 表述统一、配置合成管线、GeoX、前台可见性策略、起步路径已定）。聚焦以下结构性主题：
1. **逐层完备性**：§3.2 各层职责是否有遗漏或重叠；Service 层与 NAPI Bridge 的边界是否清晰
2. **接口契约**：NAPI ~40 函数的输入输出契约、错误码、异步回调签名是否需要在本设计阶段固化
3. **反馈回路**：配置变更→核心热加载→UI 状态同步的回路是否闭合（用户改了设置，UI 如何知道核心已生效）
4. **组合盲区**：VPN 开启中切换订阅/修改配置，运行态如何过渡不断流
5. **演进债务**：复用 proxy_core 跟随 ClashBox 升级的策略，是否存在我们改不动核心的被动局面
不要质疑已锁定的产品决策（HarmonyOS NEXT/mihomo/ArkTS/侧载/三期范围/复用 proxy_core）。
