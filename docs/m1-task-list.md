# hmos-openvpn M1 实施任务清单（语义一致性审查输入）

> 日期：2026-08-12　来源：设计文档 v0.3.1（§4 功能模块 + §5 里程碑 M1）
> 目的：展开 M1 可执行任务，供三Agent语义一致性审查（防契约/枚举/单位漂移）

---

## 0. 契约先行（M1 开工前必须冻结，防漂移四道防线）

### 0.1 数据契约（唯一事实源：proxy_core/src/main/ets/models/，禁止自定义同义类型）

| 契约 | 定义文件 | 关键字段 | M1 用途 |
|---|---|---|---|
| `Proxy` | Common.ts | name/type/latency/id/g | 节点列表 |
| `ProxyGroup` | Common.ts | type/name/proxies/now/hidden | 代理组树 |
| `ProxyType` 枚举 | Common.ts | Direct/Shadowsocks/Vmess/Trojan/Hysteria2/Selector/URLTest/... | 节点类型展示 |
| `ProxyMode` 枚举 | Common.ts | Global="GLOBAL"/Rule="RULE"/Direct="DIRECT" | 模式切换 |
| `Traffic` / `TrafficValue` | Common.ts | upRaw/downRaw；show/unit(B/KB/MB/GB/TB) | 流量图 |
| `SubscriptionInfo` | Common.ts | upload/download/total/expire | 订阅用量 |
| `LogInfo` / `LogLevel` | Common.ts | logLevel(Debug/Info/Warning/Error/Silent)/payload/time | 日志(M2) |
| `ClashConfig` / `Tun` | ClashConfig.ts | tun.enable/stack/mtu/dns-hijack 等 | 配置编辑 |
| `DnsEnhancedMode` / `TunStack` | ClashConfig.ts | fake-ip/redir-host；system/gvisor/mixed | settings |
| `UpdateConfigParams` | ClashConfig.ts | profile-id/config/params(is-patch/is-compatible/selected-map/override-dns/test-url) | 配置下发 |
| `VpnOptions` | FlClashVpnService.ts | enable/port/ipv4Address/ipv6Address/routeAddress/dnsServerAddress | VPN 状态 |
| `CoreState`（设计§3.5.1） | 设计文档 | Idle/Booting/Running/Reloading/Stopping/Error(subCode) | 全局状态 |

### 0.2 单位与口径约定（全链路唯一）

| 约定 | 值 | 说明 |
|---|---|---|
| 流量单位 | 字节（Byte）原生数值 | Traffic.upRaw/downRaw 是字节；显示经 TrafficValue 换算 B/KB/MB/GB/TB（1024 进制） |
| 延迟单位 | 毫秒（ms） | Proxy.latency / healthCheck 返回值 |
| 时间戳 | Unix 秒（number） | SubscriptionInfo.expire / LogInfo.time |
| 端口默认值 | 7890（mixed-port） | getVpnOptions 实测返回 7980，需对齐（见待确认） |
| 订阅流量 header | `subscription-userinfo: upload=X; download=X; total=X; expire=X` | SubscriptionInfo.formHString 解析 |

### 0.3 术语→标识符映射表

| 术语 | 标识符 | 位置 |
|---|---|---|
| 订阅 | Profile / profile-id | proxy_core Profile.ts / UpdateConfigParams |
| 节点 | Proxy | Common.ts |
| 代理组 | ProxyGroup | Common.ts |
| 模式 | ProxyMode | Common.ts |
| 流量 | Traffic | Common.ts |
| 当前选中 | now（ProxyGroup.now） | Common.ts |
| 延迟 | latency / DelayInfo.value | Common.ts / SocketProxyService |
| 隧道状态 | TunnelState（direct/global/rule/script/None） | ClashConfig.ts |

---

## 1. M1 任务清单

### T1 应用框架（UI 基建）
- [ ] T1.1 Navigation 主导航（8 页签：home/proxies/profiles/connections/rules/logs/settings + unlock 预留），展开态左侧栏布局（对齐 Clash Verge _layout.tsx 结构）
- [ ] T1.2 主题系统：亮/暗/跟随系统三档（色值用原版提取：#007AFF/#F5F5F5 亮、#0A84FF/#2E303D 暗），@Provide 全局注入
- [ ] T1.3 i18n 框架：string.json zh/en 双套，M1 全部用户可见字符串入库
- [ ] T1.4 CoreState 全局状态管理：Idle/Booting/Running/Reloading/Stopping/Error 派生各页渲染

### T2 Service 层（数据访问，经 NAPI/SocketProxyService）
- [ ] T2.1 核心生命周期服务：initClash（工作目录 filesDir/ClashBox）、核心状态查询（vpnConfigIsLoad/getRuntime）
- [ ] T2.2 SocketProxyService 封装：RPC 客户端（连 clash_go.sock），29 种 ClashRpcType 操作的 ArkTS 封装
- [ ] T2.3 配置合成管线（§3.6 三步法）：订阅原文+覆写层→lint→validateConfig→applyConfig；single-flight 防并发
- [ ] T2.4 状态唯一来源表落码：用户偏好→Preferences KV；订阅元数据→RDB；运行时配置→filesDir

### T3 profiles 订阅页（M1 核心）
- [ ] T3.1 订阅列表：增删改、切换激活、拖拽排序（对齐 Clash Verge profiles.tsx）
- [ ] T3.2 订阅导入：URL 导入（HTTPS 强制+证书校验）、文件导入、更新订阅
- [ ] T3.3 订阅用量展示：SubscriptionInfo（upload/download/total/expire）解析展示
- [ ] T3.4 节点预览：订阅内节点列表展示

### T4 proxies 代理页
- [ ] T4.1 代理组树：ProxyGroup 列表（Selector/URLTest/Fallback/LoadBalance/Relay 过滤展示）
- [ ] T4.2 节点延迟测速：asyncTestDelay（组级并发测速）
- [ ] T4.3 切换节点：changeProxy(group, name)，刷新 ProxyGroup.now

### T5 home 首页
- [ ] T5.1 VPN 开关：startVpnExtensionAbility/stop（ClashVpnAbility 已有），显示 CoreState
- [ ] T5.2 模式切换卡：ProxyMode（Rule/Global/Direct）三态切换
- [ ] T5.3 实时流量图：getTraffic 1Hz 轮询，Canvas 绘制（对齐 enhanced-canvas-traffic-graph.tsx）
- [ ] T5.4 当前代理卡：显示当前选中节点
- [ ] T5.5 IP 信息卡：直连第三方查询出口 IP（默认直连，隐私说明）

### T6 settings 基础
- [ ] T6.1 主题三档切换、语言切换
- [ ] T6.2 端口设置（mixed-port，默认 7890）
- [ ] T6.3 DNS 配置（fake-ip/redir-host/nameserver）——L3 级变更
- [ ] T6.4 TUN 栈选择（system/gvisor/mixed）——L3 级变更

### T7 平台能力
- [ ] T7.1 GeoX 数据：geoip.metadb/geosite.dat assets 内置 + 应用内更新（updateGeoData）
- [ ] T7.2 VPN 断连重连与 fd 资源清理（§4 要求，M1 范围）
- [ ] T7.3 后台前台可见性策略实测（灭屏 30 分钟存活率记录）

### T8 M1 验收
- [ ] T8.1 M1 退出门：固定测试订阅（≥3 节点）下 curl https://www.gstatic.com/generate_204 返回 204/200 且 <3000ms，流量图 Rx/Tx 非零
- [ ] T8.2 nativeVersion() ABI 握手（启动 0.5s 内校验）
- [ ] T8.3 现场日志一键导出

---

## 2. 契约/口径待确认项（审查时一并裁决）

1. **端口 7980 vs 7890**：getVpnOptions 真机实测返回 `port: 7980`（ClashBox 默认），设计文档/Clash Verge 默认 7890——M1 默认端口定哪个？（建议跟随实测 7980，ClashBox 生态一致）
2. **subscription-userinfo 展示字段**：expire 为 0 时不展示到期时间（对齐 Clash Verge 行为）
3. **Traffic 轮询频率**：设计 §3.5 定 1Hz——T5.3 需确认 getTraffic 是瞬时值还是累计值（决定画图方式）

---

## 3. 验证请求（语义一致性审查）

请三位审查者针对本 M1 任务清单审查：
1. **语义一致性**：任务清单中的契约字段/枚举/单位/术语与设计文档 v0.3.1（§3.7 接口契约、§3.8 状态归属、§4 功能模块）逐字对齐；有无自创同义类型/单位混用（如字节 vs KB、ms vs s）
2. **完备性**：设计文档 M1 范围（§5 M1 列表）每项都有任务承接；无遗漏无重复
3. **可执行性**：每任务验收可测试、依赖成立（如 T5.3 依赖 T2.2）
4. **契约冻结**：§0 契约清单是否完整覆盖 M1 全部数据交互；待确认项（端口/轮询）裁决建议
不要质疑已锁定的产品决策（M1 范围、三期结构、复用 proxy_core、NAPI 直连）。
