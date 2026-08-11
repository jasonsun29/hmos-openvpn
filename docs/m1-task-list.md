# hmos-openvpn M1 实施任务清单 v2（三Agent审查共识修复版）

> 日期：2026-08-12　来源：设计文档 v0.3.1 + 三Agent R4 语义一致性审查（GLM/MiniMax/Kimi 三方共识修复）
> v2 变更：契约补全（Profile/DelayInfo/ClashRpcType 完整枚举/latency 哨兵/subCode）、三项待确认裁决、页签 M1/M2 归属、每任务验收口径

---

## 0. 契约先行（唯一事实源：proxy_core/src/main/ets/，禁止自定义同义类型）

### 0.1 数据契约（完整，无省略号）

| 契约 | 定义文件 | 关键字段 | M1 用途 |
|---|---|---|---|
| `Proxy` | Common.ts | name/type/latency?(number,ms)/id?/g?（=所属代理组名，ClashBox 源码字段，收藏分组用）/isShowFavoriteProxy? | 节点列表 |
| `ProxyGroup` | Common.ts | type/name/proxies[]/now(当前选中)/hidden?/icon? | 代理组树 |
| `ProxyType` 枚举（全量） | Common.ts | Direct/Reject/Compatible/Pass/Shadowsocks/Vmess/Trojan/WireGuard/Hysteria/Hysteria2/Tuic/Selector/URLTest/Fallback/LoadBalance/Relay/Unknown | 节点类型展示 |
| `ProxyMode` 枚举 | Common.ts | Global="GLOBAL"/Rule="RULE"/Direct="DIRECT"（左侧 ArkTS 标识符，右侧 RPC 字符串值，setMode 传字符串） | 模式切换 |
| `TunnelState` 枚举 | ClashConfig.ts | Direct="direct"/Global="global"/Rule="rule"/Script="script"/None="None" | 运行时模式态 |
| `Traffic` / `TrafficValue` | Common.ts | upRaw/downRaw（**累计字节数**）；show/unit(B/KB/MB/GB/TB，1024 进制) | 流量图 |
| `SubscriptionInfo` | Common.ts | upload/download/total/expire（Unix 秒，**0=无到期不展示**）/static formHString(header)（**源码真实命名，非笔误**） | 订阅用量 |
| `Profile` | Profile.ts | id/url/name/type(remote/local)/interval/lastUpdate/options 等 | 订阅列表 |
| `DelayInfo` | Common.ts（SocketProxyService 返回） | value:number(ms)/time:number/error? | 测速结果 |
| `LogInfo` / `LogLevel` | Common.ts | logLevel(Debug/Info/Warning/Error/Silent/Unknown)/payload/time | 日志(M2) |
| `ClashConfig` / `Tun` | ClashConfig.ts | tun.enable/stack/mtu/dns-hijack 等 | 配置编辑 |
| `DnsEnhancedMode` / `TunStack` | ClashConfig.ts | fake-ip/redir-host；system/gvisor/mixed | settings |
| `UpdateConfigParams` | ClashConfig.ts | profile-id/config/params(is-patch/is-compatible/selected-map/override-dns/test-url) | 配置下发 |
| `VpnOptions` | FlClashVpnService.ts | enable/port/ipv4Address/ipv6Address/routeAddress/dnsServerAddress | VPN 状态 |
| `CoreState` | Common.ts（M1 落码） | Idle/Booting/Running/Reloading/Stopping/Error(subCode) | 全局状态 |
| `Error.subCode` 枚举（M1 覆盖） | Common.ts | ABI_MISMATCH(1)/SUBSCRIPTION_FETCH_FAILED(2)/VPN_START_FAILED(3)/CONFIG_VALIDATE_FAILED(4)/CORE_INIT_FAILED(5) | 错误文案映射 |
| `ClashRpcType` 枚举（**27 项全量**） | IClashManager.ts | queryTrafficNow/queryTunnelState/queryTrafficTotal/queryProxyGroup/queryProviders/changeProxy/healthCheck/updateProvider/uploadProvider/queryConnections/closeConnection/clearConnections/load/startClash/stopClash/validConfig/reset/getCountryCode/updateGeoData/registerOnMessage/getRequestList/clearRequestList/setLogObserver/stopLogObserver/vpnOptions/setOptionState/GetVpnRunTime/VpnConfigInited | M1 用子集：queryTrafficNow/queryProxyGroup/changeProxy/healthCheck/load/validConfig/startClash/stopClash/vpnConfigIsLoad/vpnOptions/setOptionState/getCountryCode |

### 0.2 单位与口径约定（全链路唯一）

| 约定 | 值 | 说明 |
|---|---|---|
| 流量单位 | 字节（Byte）原生数值 | upRaw/downRaw 累计字节；显示经 TrafficValue 换算（1024 进制） |
| 流量图实现 | 1Hz 轮询 + 前端差分 | currentRaw - previousRaw = 每秒速率（裁决定案） |
| 延迟单位 | 毫秒（ms） | Proxy.latency / DelayInfo.value；**超时=5000ms，未测=0，UI 显示 "--"** |
| 测速 URL | 与 test-url 对齐，默认 generate_204 | T4.2 并发上限 10 |
| 时间戳 | Unix 秒（number） | SubscriptionInfo.expire/LogInfo.time；Date 对象桥接时 *1000（序列化前） |
| 端口默认值 | **7980**（实测裁决） | ClashBox 生态实测值即事实源；settings 页用户可改 + 冲突检测 |
| 订阅流量 header | `subscription-userinfo: upload=X; download=X; total=X; expire=X` | **大小写不敏感**（HTTP/2 header 全小写） |
| generate_204 验收 | E2E 耗时 <3000ms | 从发起请求到收到 204/200 响应（含代理建立） |
| Rx/Tx 映射 | Rx=downRaw, Tx=upRaw | 术语统一 |

### 0.3 术语→标识符映射表

| 术语 | 标识符 | 位置 | 备注 |
|---|---|---|---|
| 订阅 | Profile / profile-id | Profile.ts / UpdateConfigParams | SubscriptionInfo 为 Clash 生态保留命名，从属 Profile 表示用量元数据 |
| 节点 | Proxy | Common.ts | |
| 代理组 | ProxyGroup | Common.ts | |
| 模式（UI 态） | ProxyMode | Common.ts | 用户选择，三态 |
| 模式（运行时） | TunnelState | ClashConfig.ts | 实际运行态，M1 隐藏 None/Script 入口但保留服务端支持 |
| 当前选中 | now（ProxyGroup.now） | Common.ts | 选中态持久化走 selected-map（T2.4） |
| 延迟 | latency / DelayInfo.value | Common.ts / SocketProxyService | 超时 5000ms/未测 0/显示 "--" |
| 测速 | asyncTestDelay | SocketProxyService | 与 test-url 对齐 |
| 激活订阅 | activeProfileId | Preferences | |
| 配置覆写 | Override | UpdateConfigParams.params | |
| 隧道状态 | TunnelState | ClashConfig.ts | 与 TUN 虚拟网卡区分 |
| 流量 | Traffic | Common.ts | Rx=downRaw, Tx=upRaw |
| 分组 | Group | i18n 中英同 key | |

---

## 1. M1 任务清单（含验收口径）

### T1 应用框架（UI 基建）
- [ ] T1.1 Navigation 主导航：**M1 渲染 4 页签**（home/proxies/profiles/settings），connections/rules/logs **M2 占位**（路由注册但显示"开发中"）
  - 验收：4 页签可切换，占位页不闪退
- [ ] T1.2 主题系统：亮/暗/跟随系统三档（#007AFF/#F5F5F5 亮、#0A84FF/#2E303D 暗），@Provide 注入
  - 验收：三档切换即时生效，色值正确
- [ ] T1.3 i18n：string.json zh/en 双套，M1 全部字符串入库
  - 验收：语言切换全页面文案更新
- [ ] T1.4 CoreState 状态管理：Idle/Booting/Running/Reloading/Stopping/Error(subCode)
  - 验收：状态转换矩阵（initClash→Booting，vpnStarted→Running，reload→Reloading→Running，vpnStopped→Idle，异常→Error）逐项可观测
- [ ] T1.5 CoreState.Error 通用错误层：subCode→i18n 文案，重试/查看日志入口
  - 验收：5 种 subCode 各有文案，重试按钮有效

### T2 Service 层
- [ ] T2.1 核心生命周期：initClash(filesDir/ClashBox) + ensureDirs() + seedDefaultConfig() + Preferences 默认值
  - 验收：首次启动目录/默认配置自动创建，0.5s 内 nativeVersion() 校验
- [ ] T2.2 SocketProxyService 封装：RPC 客户端 + M1 子集（11 项）ArkTS 封装
  - 验收：queryProxyGroup 返回真实数据，changeProxy 生效
- [ ] T2.3 配置合成管线：lint→validateConfig→applyConfig + single-flight(key=profile-id+op)
  - 验收：合法/缺字段/invalid yaml/并发 apply 4 例测试矩阵；validateConfig 失败自动回滚上一份有效配置
- [ ] T2.4 状态归属落码：偏好→Preferences KV；订阅元数据→RDB；运行时配置→filesDir；**选中态→selected-map 持久化**
  - 验收：重启后节点选中保持，字段归属表逐项核对

### T3 profiles 订阅页
- [ ] T3.1 订阅列表：增删改、切换激活、拖拽排序
  - 验收：列表操作即时生效，激活态高亮
- [ ] T3.2 订阅导入：URL(HTTPS 强制+证书校验；HTTP 需弹窗确认风险)+文件导入+更新
  - 验收：https 失败返回明确错误码；http 弹窗确认后放行
- [ ] T3.3 订阅用量：SubscriptionInfo.formHString 解析展示；expire=0 不展示到期
  - 验收：header 解析正确，大小写不敏感
- [ ] T3.4 节点预览：订阅内节点列表

### T4 proxies 代理页
- [ ] T4.1 代理组树：ProxyGroup 渲染（Selector/URLTest/Fallback/LoadBalance/Relay）
  - 验收：各组类型图标正确
- [ ] T4.2 节点测速：asyncTestDelay 组级并发（≤10），超时 5000ms 标 timeout
  - 验收：100 节点 5s 内出全量结果
- [ ] T4.3 切换节点：changeProxy(group,name) + selected-map 持久化
  - 验收：切换即时生效，重启后选中保持

### T5 home 首页
- [ ] T5.1 VPN 开关：startVpnExtensionAbility/stop（ClashVpnAbility 已有，M0b-3 验证链路）
  - 验收：授权→连接→状态"已连接"，断开→"未连接"
- [ ] T5.2 模式切换卡：ProxyMode 三态（Rule/Global/Direct）
  - 验收：切换后 TunnelState 跟随
- [ ] T5.3 实时流量图：1Hz 轮询 + 差分 + Canvas（对齐 enhanced-canvas-traffic-graph.tsx）
  - 验收：Rx/Tx 非零，B/KB/MB 刻度自适应，灭屏停轮询亮屏恢复
- [ ] T5.4 当前代理卡：显示 ProxyGroup.now
  - 验收：切换节点后即时更新
- [ ] T5.5 IP 信息卡：api.ipify.org?format=json，超时 5s 失败显示"--"，settings 可关闭
  - 验收：显示"本地出口"文案（非代理出口），失败态正确

### T6 settings 基础
- [ ] T6.1 主题三档 + 语言切换
- [ ] T6.2 端口设置（**默认 7980**）+ 冲突检测
  - 验收：修改后 applyConfig 生效，端口冲突提示
- [ ] T6.3 DNS 配置（fake-ip/redir-host/nameserver）——L3 变更（重建 TUN）
  - 验收：切换 DNS 模式后 VPN 重建且连接恢复
- [ ] T6.4 TUN 栈（system/gvisor/mixed）——L3 变更
  - 验收：切换后 VPN 重建且连接恢复

### T7 平台能力
- [ ] T7.1 GeoX 数据：assets 内置 + 版本检查按需更新（包体积预算 ≤20MB）
  - 验收：启动检查内置 vs 缓存版本，settings 手动触发入口
- [ ] T7.2 VPN 断连重连 + fd 清理清单（clash_go.sock/TUN fd/DNS hijack fd/geo mmap）
  - 验收：连续断连 50 次 fd 数回基线 ±k（/proc/self/fd 观测）
- [ ] T7.3 后台策略：T7.3a 保活编码（长定时器/前台可见性通知）+ T7.3b 存活率观测报告
  - 验收：灭屏 30min 存活率 ≥95%，断流自动恢复 ≤10s

### T8 M1 验收
- [ ] T8.1 退出门：本地固化测试配置（fixture，不依赖外部订阅）下，经代理请求 generate_204 E2E <3000ms；流量图 Rx/Tx 非零
- [ ] T8.2 nativeVersion() ABI 握手（启动 0.5s 内）
- [ ] T8.3 日志一键导出（含脱敏：订阅 URL/节点信息打码）

---

## 2. 三Agent 审查裁决记录（R4）

| # | 阻断/重要项 | 裁决 |
|---|---|---|
| 1 | 端口 7890/7980 矛盾 | **7980**（实测即事实源），§0.2/T6.2 已同步 |
| 2 | getTraffic 语义 | **累计字节 + 前端 1Hz 差分**（§0.2 已写入） |
| 3 | formHString 疑似笔误 | **保留源码命名 formHString**（proxy_core 真实方法名，非笔误） |
| 4 | Proxy.g 语义不明 | **保留 g**（=所属代理组名，ClashBox 源码字段） |
| 5 | 页签归属 | **M1 仅 4 页签，connections/rules/logs M2 占位** |
| 6 | 契约缺口 | Profile/DelayInfo/ClashRpcType(27项)/subCode/latency 哨兵已补全 |
| 7 | "29 种 RPC" | **修正为 27 项**（源码实测），M1 用子集 11 项 |
| 8 | 每任务验收 | 全部任务补验收口径（见各任务行） |
| 9 | 审查缺设计文档原文 | 本版含完整契约自洽；M1 收尾再做一次设计对齐审查时附原文 |
| 10 | TunnelState/ProxyMode 边界 | ProxyMode=UI 三态，TunnelState=运行时态，§0.3 已注明 |

> 附：项目代号 hmos-openvpn 与 mihomo 技术栈语义不符——已记录，对外发布前评估更名（不阻塞 M1）。
