# hmos-openvpn 设计文档 v0.1

> 版本：v0.1（评审前草案）　日期：2026-08-11　作者：Hermes Agent
> 项目：HarmonyOS NEXT 纯鸿蒙 VPN 应用，功能级复刻 Clash Verge Rev（v2.5.3）
> 参照实现：ClashBox（⭐4.2k，github.com/xiaobaigroup/ClashBox，master 分支，已 clone 完整源码）

---

## 1. 概述

### 1.1 目标
在 HarmonyOS NEXT 上交付一个 VPN 应用，**功能完整对齐 Clash Verge Rev v2.5.3**（用户定义的"像素级"=功能维度完整，非逐像素布局复刻）。鸿蒙落地的 native 架构参照 ClashBox 已验证的 `mihomo→.so→NAPI` 方案。

### 1.2 非目标
- 不上架 AppGallery（仅自用侧载 + 代码开源备选）
- 不兼容 HarmonyOS 4.x 及更早（不做安卓 AOSP 适配）
- 不逐像素复刻桌面布局（Pura X Max 展开态用左侧栏，折叠态紧凑适配）
- 不实现独立 native daemon（鸿蒙沙箱不允许，核心必须 .so 动态库）

### 1.3 成功标准
- M1：能导入订阅、解析节点、开启系统 VPN（VpnExtensionAbility）、选择节点、看到流量图，全程真机可用
- M2：connections/rules/logs/settings 全量、配置可编辑
- M3：unlock 流媒体检测、主题色自定义、鸿蒙服务卡片
- 全程在 Pura X Max 真机（HOP-AL10，HarmonyOS 7.0.0）调试验收

---

## 2. 术语表

| 术语 | 定义 |
|---|---|
| **mihomo** | Clash Meta 的继任核心（Go），提供代理协议、规则匹配、TUN、RESTful API；本项目 v1.17.1（与 ClashBox 对齐） |
| **FlClash / libflclash.so** | FlClash 项目对 mihomo 的封装层（Go cgo + ohos-napi 桥），编译产物为 74MB arm64 .so |
| **ohos-napi** | OpenHarmony 的 Node-API Go 绑定库（github.com/likuai2010/ohos-napi v1.0.3），让 Go 函数直接以 js.Env/js.Value 形态暴露给 ArkTS |
| **go-ohos 工具链** | OpenHarmony SIG 维护的 Go 移植（非官方），支持 GOOS=linux + cgo -buildmode=c-shared -tags "ohos with_gvisor" |
| **gvisor-ohos** | ClashBox 魔改的 gvisor 网络栈（go.mod replace 指向本地 ./gvisor-ohos），适配鸿蒙 TUN |
| **VpnExtensionAbility** | 鸿蒙系统 VPN 扩展能力（API 11+，@kit.NetworkKit），提供 TUN fd 和生命周期 |
| **NAPI Bridge** | C++ 桥接层（proxy_core/src/main/cpp），ArkTS 经它调 .so |
| **HDC** | 鸿蒙调试桥（HarmonyOS Debug Bridge），连真机用 |
| **HAP** | HarmonyOS Ability Package，应用安装包 |

---

## 3. 架构总览

### 3.1 分层架构

```
┌─────────────────────────────────────────────┐
│  ArkTS UI 层（ArkUI + Navigation 框架）        │  ← 8大页面，对照 Clash Verge React 组件树翻译
│  @State/@Provide 状态管理，中英双语 i18n        │
├─────────────────────────────────────────────┤
│  Service 层（ArkTS）                            │  ← 业务逻辑：订阅管理/延迟测速/流量统计/配置编辑
│  数据经 NAPI Bridge 或 mihomo RESTful API       │
├─────────────────────────────────────────────┤
│  NAPI Bridge（C++，proxy_core/src/main/cpp）    │  ← ArkTS ↔ native .so 的类型转换与生命周期
├─────────────────────────────────────────────┤
│  libflclash.so（Go c-shared，mihomo v1.17.1）  │  ← 代理核心：协议/规则/TUN/流量/连接
│  经 ohos-napi 暴露 ~40 个函数给 ArkTS           │
├─────────────────────────────────────────────┤
│  VpnExtensionAbility（系统 VPN）                │  ← 创建 TUN fd，交给核心 startTun(fd)
│  后台 dataTransfer 保活                          │
└─────────────────────────────────────────────┘
```

### 3.2 关键数据流
- **开启 VPN**：UI → vpnExtension.startVpnExtensionAbility → VpnExtensionAbility.onCreate 拿到 TUN fd → NAPI startTun(fd, callback) → mihomo 接管全部流量
- **数据查询**（节点/流量/连接/日志）：ArkTS 经 NAPI 直接调 .so 导出函数（getProxies/getTraffic/getConnections/startLog），**不走 RESTful API**（ClashBox 实证路径，比 Clash Verge 的 HTTP 轮询更直接）
- **配置下发**：UI 编辑 YAML → NAPI updateConfig(yamlString) → mihomo 热加载

### 3.3 与 Clash Verge 的架构差异（重要决策点）
Clash Verge 是 `前端 ↔ RESTful API(:9090) ↔ 独立 mihomo 进程`；鸿蒙不能跑独立进程，改为 `ArkTS ↔ NAPI ↔ .so 内嵌核心`。**功能对齐，但数据通路从 HTTP 轮询改为 NAPI 直连**——这是鸿蒙强制的架构改编，ClashBox 已验证。

---

## 4. 功能模块（对照 Clash Verge 八页面）

| 页面 | Clash Verge 行数 | 鸿蒙实现要点 | 里程碑 |
|---|---|---|---|
| profiles 订阅 | 1066 | 增删改/远程更新/YAML编辑/导入(URL/文件/二维码)/拖拽排序/合并脚本 | M1核心+M2编辑 |
| proxies 代理 | 206 | 代理组树/延迟测速(asyncTestDelay)/切换节点 | M1 |
| home 首页 | 394 | 流量图(Canvas)/当前代理/模式切换/IP信息/系统信息 | M1 |
| connections 连接 | 340 | 活跃连接表格(getConnections)/排序/关闭(closeConnection) | M2 |
| rules 规则 | 104 | 规则列表展示 | M2 |
| logs 日志 | 207 | startLog 流式回调/级别过滤/搜索 | M2 |
| settings 设置 | 117 | 端口/模式/主题/语言/VPN开关 | M1基础+M2全量 |
| unlock 解锁 | 503 | 流媒体检测(Netflix/Disney+等)逐节点 | M3 |

另需鸿蒙特有：VpnExtensionAbility 服务、后台保活、服务卡片（M3）、折叠屏双态布局。

---

## 5. 里程碑

### M0 工程奠基（先行，不属功能）
- 建鸿蒙工程骨架（entry + proxy_core 模块，参照 ClashBox 目录）
- 装 go-ohos 工具链，交叉编译 mihomo v1.17.1 → libflclash.so（复用 ClashBox build.sh 链路 + gvisor-ohos + ohos-napi）
- NAPI Bridge C++ 层搭通，ArkTS 能调到 initClash
- 真机签名跑通空 HAP（开发者账号签名）
- **退出门**：真机装上空壳，NAPI 调通核心版本号

### M1 核心可用
- profiles：导入(URL)/更新/切换订阅、节点列表
- proxies：代理组树 + 延迟测速 + 切换
- home：VPN 开关（VpnExtensionAbility 起停）+ 模式切换（规则/全局/直连）+ 实时流量图
- settings 基础：主题三档、语言、端口
- **退出门**：真机上导入真实订阅→开启 VPN→YouTube 通→流量图跳动

### M2 完整对齐
- connections/rules/logs 三页全量
- profiles 高级：YAML 编辑、二维码导入、合并/脚本
- settings 全量
- **退出门**：对照 Clash Verge 功能清单逐项打勾，除 M3 项外全绿

### M3 锦上添花
- unlock 流媒体检测
- 主题色自定义
- 鸿蒙服务卡片
- **退出门**：全功能对齐

---

## 6. 风险登记册

| 风险 | 等级 | 缓解 |
|---|---|---|
| go-ohos 工具链非官方、Go runtime 在鸿蒙稳定性未知 | 🔴 高 | 直接复用 ClashBox 已验证的编译链路（build.sh + go-ohos + gvisor-ohos），不自己造；先 M0 验证编译跑通再往下 |
| VpnConfig.routes 在 API 23 前不生效 | 🟡 中 | 目标 API 23+，SDK 已 6.1.1(API 24)、真机 7.0.0，天然规避 |
| MANAGE_VPN 等受限权限未确认 | 🟡 中 | M0 在真机实测 VPN 起停，验证权限清单 |
| 后台保活被系统杀 | 🟡 中 | 申请 KEEP_BACKGROUND_RUNNING + dataTransfer 长时任务；实测观察 |
| mihomo 核心 74MB 包体积 | 🟢 低 | 自用侧载可接受；必要时裁剪协议 |
| 界面折叠屏双态适配工作量 | 🟢 低 | 展开态优先，折叠态用 ArkUI 响应式降级 |

---

## 7. 开放项
1. go-ohos 工具链的具体获取/安装方式（需调研 OpenHarmony SIG，M0 第一个任务）
2. MANAGE_VPN / 受限权限的准确清单（M0 真机实测确认）
3. 是否直接 fork ClashBox 起步 vs 从零搭建只参考其 proxy_core（见 ADR 候选）

---

## 8. 验证请求（R1：细节正确性审查）

请三位审查者**只针对本设计文档**做内部矛盾、决策缺口、规则可执行性审查，重点关注：
1. 架构分层与数据流是否自洽（NAPI 直连 vs RESTful 的决策是否说清了）
2. M0 的 go-ohos 工具链依赖是否是最大不确定点，M0 退出门是否可测试
3. 功能模块与里程碑的映射有无遗漏（对照 Clash Verge 八页面）
4. 是否有自相矛盾或未闭合的决策
不要重复讨论已锁定的产品决策（HarmonyOS NEXT / mihomo / ArkTS / 侧载 / 三期范围——这些是用户拍板的）。
