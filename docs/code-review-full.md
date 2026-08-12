# hmos-openvpn 两轮代码审查完整报告（含验证结论）

| 项目 | 值 |
|---|---|
| 项目 | hmos-openvpn（HarmonyOS NEXT 代理客户端，内核 mihomo/Clash Meta） |
| 审查方式 | 三轮独立审查：Kimi-K3 静态+真机验证、MiniMax M3 静态审查、Kimi-K3 第二轮深度验证 |
| 证据来源 | 全量源码阅读 + 真机日志（hilog/flclashGo）+ devecocli 官方文档 + hmos-arkts-knowledge-retriever |
| 审查日期 | 2026-08-12 |
| 当前状态 | M1+M2 真机验收通过（订阅→VPN→分流→节点→出口IP→YouTube 全通） |

---

## 0. 审查方法说明

- **K3 第一轮**：基于源码阅读 + 真机调试经验（M1/M2 开发全程的 8 个真机修复）
- **M3**：纯静态分析（读到 REVIEW.md，覆盖工程配置/Go 侧/资源泄漏等 K3 未覆盖面）
- **K3 第二轮**：带着 M3 的全部发现逐项验证（用官方文档 + 源码证据），并深挖测速问题根因

---

## 1. 问题总表（按严重性分级，标注验证结论）

### 🔴 P0 级（影响核心功能/严重 UX）

| # | 问题 | 提出者 | 验证结论 | 证据 | 修复方案 |
|---|------|--------|----------|------|----------|
| P0-1 | **测速 URLTest 全部超时，testing 卡死** | K3-1 | ✅ 验证通过 | 真机日志：UI 发 healthCheck(6) 请求，Go 侧无 URLTest 执行日志 | 见 §2 完整因果链与 4 连修 |
| P0-2 | **socket 层 10s 超时 vs 核心 1.5s 超时矛盾** | K3-2 (NEW-1) | ✅ 验证通过（本轮新定位） | SocketProxyService.ets:236 `setTimeout(..., 10000)` vs healthCheckWithTimeout 传 1500ms | healthCheck 独立短超时（3s） |
| P0-3 | **error toast 轰炸** | K3-2 (NEW-2) | ✅ 验证通过（本轮新定位） | SocketProxyService.ets:206 每次 error RPC 都 showToast | toast 限频（1s 最多 1 次） |
| P0-4 | **VPN 断连无 UI 同步（假连接 bug）** | M3 | ✅ 验证通过（官方文档确认） | 官方 FAQ「阶段四场景1」：VPN Extension 进程死亡时系统自动清理但不通知 UI；`createVpnObserver()` 只有 onAuthorizationResult，无连接状态监听 | UI 心跳探测（5s ping socket，3 次失败复位 vpnOn） |
| P0-5 | **setMode() 的 test-url 用 HTTP（与 ClashVpnAbility 的 HTTPS 不一致）** | K3-1 (P3) | ✅ 验证通过 | Home.ets:112 `'test-url': 'http://...'` vs ClashVpnAbility 已改 https | 统一 HTTPS |
| P0-6 | **Index.ets（M0b-1 验证页）残留在 main_pages.json** | M3 | ✅ 验证通过 | main_pages.json 含 "pages/Index"，Index.ets 有 initClash NAPI 调用（UI 进程加载 Go 核心的隐患） | 从 main_pages.json 移除 |

### 🟡 P1 级（影响架构/可维护性）

| # | 问题 | 提出者 | 验证结论 | 证据 | 修复方案 |
|---|------|--------|----------|------|----------|
| P1-1 | **双通道并存（NAPI + IPC 混用）** | M3 | ✅ 验证通过（比 M3 说的更严重） | SocketProxyService.ets:14 UI 进程直接 `import from 'libflclash.so'`，同时走 IPC；两份 ClashRpcType 枚举（IClashManager.ts vs ipc.go）手动同步 | UI 永远走 IPC，NAPI 只在 VPN 进程 |
| P1-2 | **激活订阅状态 4 处同步** | M3 | ✅ 验证通过 | Preferences + 状态文件 + RDB + Go 内存，setActiveProfileId 和 loadActiveConfig 各复制一次 yaml | ActivationStore 单例 |
| P1-3 | **IPC 消息帧处理脆弱（10240 字节假设 + EOF 分割）** | M3 | ✅ 验证通过 | ipc.go:34 单次 Read 假设 ≤10KB 一次到达；订阅配置 JSON 常 >10KB；ArkTS 侧 debounce 200ms 拼消息 | Go 侧循环 Read 完整 JSON（或 length-prefix 帧） |
| P1-4 | **TUN 重建缺失（DNS/TUN 栈设置不生效）** | M3 | ✅ 验证通过 | Settings.ets applyDnsMode/applyTunStack 只 patchConfig，无 stopTun+startTun | L3 变更走 stopVpn → loadActiveConfig → startVpn |
| P1-5 | **loadConfig profile-id 拼接 hack** | K3-2 (NEW-3) | ✅ 验证通过（本轮新发现） | SocketProxyService.ets:51 `id + "/config"`；ArkTS getProfilePath(<id>/config.yaml) vs Go getProfilePath(<id>.yaml) 路径不一致，用拼接掩盖 | 统一路径（改 ArkTS 侧 getProfilePath 与 Go 一致） |
| P1-6 | **testing 卡死自愈竞态** | K3-2 (NEW-4) | ✅ 验证通过（本轮新发现） | Proxies.ets:209 连点两次：第二次点击重置 testing=false 但第一次 testGroup 还在跑 | generation 计数器 |
| P1-7 | **Home 页"当前代理"不随节点切换更新** | K3-1 (P2) | ✅ 验证通过 | HomePage 只在 aboutToAppear + toggleVpn 后 refreshCurrentProxy，无事件监听 | EventHub 或 pollTraffic 顺带刷新 |
| P1-8 | **证书硬编码绝对路径** | M3 | ✅ 验证通过 | build-profile.json5 写死 /Users/jason/.ohos/config/... | local.properties / 环境变量 |
| P1-9 | **调试日志未清理（任务号 tag + 循环打日志）** | K3-1 (P4) + M3 | ✅ 验证通过 | Proxies.ets:33-35 每 100+ 节点打一条 group now；tag 混乱（M0b3/T1~T11） | 语义化 tag + 清理诊断日志 |
| P1-10 | **VPN 授权结果未监听** | K3-2 (NEW-5) | ✅ 验证通过（本轮新发现） | 官方 API 26 `onAuthorizationResult` 存在未使用；用户拒绝授权时 vpnState 卡在 vpn_requesting | 注册 onAuthorizationResult |
| P1-11 | **应用退后台 socket 断开未处理** | K3-2 (NEW-6) | ✅ 验证通过（官方文档确认） | 官方「使用Socket访问网络」：退后台后 Socket 可能断开，回前台需重建 | aboutToAppear 强制刷新 |

### 🟢 P2 级（M3 里程碑修/优化）

| # | 问题 | 提出者 | 验证结论 | 证据 | 修复方案 |
|---|------|--------|----------|------|----------|
| P2-1 | AppService 单一类职责过多（235 行） | M3 | ✅ 验证通过 | Preferences/主题/激活/GeoX/诊断/文件工具全在一个类 | 拆 SettingsRepository/GeoDataInstaller/DiagnosticCollector |
| P2-2 | 文件工具三处重复 | M3 + K3-1 (P13) | ✅ 验证通过 | AppService.ets / ClashVpnAbility.ets / proxy_core fileUtils.ts | 统一到 fileUtils.ts 导出 |
| P2-3 | Rules 页静态解析（可改用 getRequestList 实时统计） | M3 + K3-1 (P7) | ✅ 验证通过（M3 方案更优） | Rules.ets 文本行扫描 YAML；getRequestList（ipc.go:136）已有核心请求数据 | 改用 getRequestList 统计 rule 频率 |
| P2-4 | 核心日志无持久化 | M3 | ✅ 验证通过 | Go 侧 logrus 只打 hilog 回调，无文件落盘 | Go 侧写 filesDir/core.log + 导出 |
| P2-5 | 订阅自动更新 worker 缺失 | M3 | ✅ 验证通过 | Profile.ets:48-60 autoUpdate=true / autoUpdateDuration=60s 是死字段，无定时器 | SubscriptionUpdater setInterval |
| P2-6 | i18n 硬编码中文（toast/按钮） | M3 + K3-1 (P12) | ✅ 验证通过 | '请先开启 VPN'/'端口无效'/'请输入订阅 URL' 等硬编码 | 全部走 $r 资源 |
| P2-7 | BackgroundKeepAliveService.stop 未取消通知 | M3 | ✅ 验证通过 | 无 notificationManager.cancelNotification | 补 cancelNotification |
| P2-8 | SocketStubService.startService 失败时 clientPool 泄漏 | M3 | ✅ 验证通过 | listen 失败不清理 clientPool | catch 中清理 |
| P2-9 | Request.ts 考古层（175 行注释代码） | M3 | ✅ 验证通过 | 389 行里前 175 行是注释掉的旧实现 + rcp/http 双 import | 清理 |
| P2-10 | 品牌不一致（hmos-openvpn/fsclash/ClashBox 三套名） | M3 | ✅ 验证通过 | 应用名 OpenVPN / 数据库 fsclash.db / 目录 ClashBox | 品牌统一 |
| P2-11 | 应用名标"OpenVPN"但内核是 mihomo | M3 | ✅ 验证通过 | EntryAbility_label=OpenVPN，实际 mihomo 内核 | 品牌误导，需改名评估 |
| P2-12 | 混淆规则空跑 | M3 | ✅ 验证通过 | obfuscation-rules.txt 存在但未启用 | build-profile 开 obfuscation |
| P2-13 | @ohos.file.fs vs @kit.CoreFileKit 不统一 | M3 | ✅ 验证通过 | 项目混用两种文件 API | 统一 @kit.CoreFileKit |
| P2-14 | 单测缺失 | M3 | ✅ 验证通过 | ohosTest 只有占位 | 纯函数先补单测 |
| P2-15 | Lint 未接入 | M3 | ✅ 验证通过 | code-linter.json5 存在无 CI | hvigor lint 进 pre-commit |
| P2-16 | 隐私合规声明缺失 | M3 | ✅ 验证通过（自用侧载影响低） | module.json5 无 metadata 描述用途 | 上架前补 |

### ⚪ P3 级（后续优化/体验）

| # | 问题 | 提出者 | 验证结论 | 证据 | 修复方案 |
|---|------|--------|----------|------|----------|
| P3-1 | Canvas 尺寸硬编码 340×90 | K3-1 (P5) | ✅ 验证通过 | Home.ets:202-203 | onAreaChange 自适应 |
| P3-2 | 流量波形 shift() O(n) | K3-1 (P10) | ✅ 验证通过 | downHistory.shift() | 环形缓冲区 |
| P3-3 | formatBytes 重复 3 处 | K3-1 (P11) | ✅ 验证通过 | Home/Connections/Profiles 各一份 | 公共工具类 |
| P3-4 | Profiles 编辑对话框 position 绝对定位 | K3-1 (P8) | ✅ 验证通过 | position({x:'5%',y:'10%'}) | CustomDialog / bindSheet |
| P3-5 | 无错误边界/重试机制 | K3-1 (P9) | ✅ 验证通过 | 所有 catch 只打日志/toast | 统一 tryRunAsync + 重试 |
| P3-6 | Connections 页无搜索/过滤 | K3-1 (P6) | ✅ 验证通过 | 对比 Clash Verge connections.tsx | M3 里程碑补 |
| P3-7 | 导入本地文件订阅无 UI | M3 | ✅ 验证通过 | ProfileType.File 枚举定义了无实现 | @ohos.file.picker |
| P3-8 | GeoX 自动更新无 UI | M3 | ✅ 验证通过 | defaultGeoXMap 定义了，updateGeoData NAPI 无调用方 | Settings 加更新按钮 |
| P3-9 | updateDns NAPI 暴露但 UI 没调用 | M3 | ✅ 验证通过 | main_cgo.go:173 实现无调用方 | 删或接进设置 |
| P3-10 | 进程级保活只有 VPN 进程 | M3 | ✅ 验证通过 | UI 进程被杀后 VPN 进程可能被回收 | UI 轻量保活 |
| P3-11 | 无分享/导出配置 | M3 | ✅ 验证通过 | Profile.ets 无 toYaml/share | M3 里程碑补 |
| P3-12 | 无扫码导入 | M3 | ✅ 验证通过 | 无扫码能力 | M3 里程碑补 |
| P3-13 | EntryBackupAbility 注册未实现 | M3 | ✅ 验证通过 | module.json5:41 注册，backup_config.json 缺失 | 实现或移除 |
| P3-14 | 调试符号未剥离（-N -l） | M3 | ✅ 验证通过 | build.sh `-gcflags="all=-N -l"` | release 分支 -trimpath -ldflags |
| P3-15 | 导航用条件渲染而非 Navigation/NavDestination | K3-1 (A3) | ⚠️ 部分验证 | build() if/else 切换可用（真机验证过），但无返回栈/转场动画/页面状态保留 | M3 迁移 Navigation |

### ❌ 验证为假/不准确的发现

| # | 原发现 | 提出者 | 验证结论 | 证据 |
|---|--------|--------|----------|------|
| F-1 | **TUN 栈只有 gvisor，system 选项点了没效果** | M3 (§3.3) | ❌ **不准确** | sing_tun/server.go:453 `tun.NewStack(strings.ToLower(options.Stack.String()), stackOptions)` —— sing_tun 库本身支持 gvisor/system/mixed 多栈，栈选择是生效的；**真正的问题只是"设置后不重建 TUN"（P1-4）** |
| F-2 | **K3 第一轮认为双通道架构"已验证的正确设计"** | K3-1 (A2) | ❌ **自我修正** | M3 指出后验证：UI 进程直接 import libflclash.so 是真实架构债务（P1-1），K3 第一轮未标记为问题 |
| F-3 | **K3 第一轮认为激活状态多处同步"能用"** | K3-1 | ❌ **自我修正** | M3 指出后验证：setActiveProfileId + loadActiveConfig 各复制一次 yaml 确实冗余（P1-2） |

---

## 2. 测速卡死完整因果链（本轮最终定位）

这是**三轮审查中唯一从"现象"到"根因"完整闭环的问题**，也是真机上最影响体验的问题：

```
用户点「全部测速」
  ↓
testGroup 并发 6 个 healthCheck（Proxies.ets:73）
  ↓
每个 healthCheck → sendMessageRequest（SocketProxyService.ets:157）
  ↓
socket 层超时 = 10s（SocketProxyService.ets:236 setTimeout 10000）
  ↓
传给核心的 URLTest 超时 = 1.5s（Proxies.ets:77 healthCheckWithTimeout(name, 1500)）
  ↓
★ 矛盾点：核心 1.5s 没返回 → UI 要等 10s 才 reject
  ↓
100+ 节点 × 10s / 6 并发 ≈ 170 秒（"一直在测速中"）
  ↓
每个失败 RPC → ParseMessage error 分支 → showToast（SocketProxyService.ets:206）
  ↓
★ toast 轰炸：100+ toast 排队 → UI 假死（"没有任何反应"）
  ↓
testing 卡死自愈竞态（Proxies.ets:209 连点两次状态错乱）
```

**修复 4 连**（P0-1~P0-3 + P1-6）：
1. healthCheck 的 sendMessageRequest 独立短超时（3s），不走 10s 默认
2. error toast 限频（1s 内最多 1 次）
3. testing 用 generation 计数器防竞态
4. URLTest 超时 1500ms → 3000ms（HTTPS+TLS 握手需要时间）

---

## 3. 真机验证通过的功能清单（非问题，是已确认成果）

| 功能 | 验证结果 | 证据 |
|------|----------|------|
| 订阅导入 | ✅ | 桔子云导入成功（600GB userinfo 解析） |
| VPN 连接 | ✅ | 双进程稳定存活 + TUN 接管（tunFd 67/70/71） |
| 分流规则 | ✅ | 国内 DIRECT + 国外代理（GeoIP/DomainSuffix 日志铁证） |
| 节点连接 | ✅ | 101ms 连通（DoH 环路修复后） |
| 出口 IP | ✅ | 深圳 27.38.4.121 → 香港 220.246.101.59 |
| YouTube | ✅ | 可观看 |
| 节点切换 | ✅ | changeProxy + 对勾跳转（Button 承载 + 清空重建） |
| 连接/规则/日志页 | ✅ | 真机可见可用 |
| 配置编辑 | ✅ | TextArea 编辑 + 保存 + Go 格式同步 |
| 流量波形图 | ✅ | Canvas 蓝下载/绿上传 |
| 后台保活 | ✅ | 长时任务 + 常驻通知 |
| IP 查询 | ✅ | 多服务 fallback（ipify→ip.sb→ipip） |

**M1+M2 开发期已修复的 8 个真机问题**（历史，供参考）：
1. HAP 安装失败（NOTIFICATION_CONTROLLER 系统权限）
2. 导航点击无效（Row→Button 承载）
3. 订阅导入失败（vailConfig 契约）
4. VPN 核心 SIGSEGV（currentConfig=nil → 加载订阅配置）
5. 开关抖动（Toggle 防抖）
6. 流量全直连（tunIp 设置）
7. 配置路径不匹配（ArkTS <id>/config.yaml vs Go <id>.yaml）
8. 节点域名 DoH 解析环路（改普通 DNS 直连）

---

## 4. 修正后的综合优先级路线图

| 优先级 | 项 | 工作量 | 收益 |
|--------|---|--------|------|
| **P0** | 测速 4 连修（超时/限频/竞态/1500→3000ms） | 小 | 修复核心功能卡死 |
| **P0** | VPN 断连检测（心跳） | 小 | 修复假连接 bug |
| **P0** | setMode() test-url 统一 HTTPS | 5 分钟 | 防测速回归 |
| **P0** | Index.ets 从 main_pages.json 移除 | 5 分钟 | 发版安全 |
| **P1** | IPC 帧处理（循环 Read） | 小 | 大配置不丢消息 |
| **P1** | TUN 重建实现 | 小 | 设置项生效 |
| **P1** | 双通道统一（UI 移除 libflclash.so） | 中 | 架构主矛盾 |
| **P1** | loadConfig profile-id 重构 | 小 | 消除路径 hack |
| **P1** | Home 页当前代理事件刷新 | 小 | UI 一致性 |
| **P1** | 证书路径 env 化 | 小 | 跨机器编译 |
| **P2** | ActivationStore 单例 | 中 | 状态同步漏洞 |
| **P2** | AppService 拆分 | 中 | 可维护性 |
| **P2** | Rules 页 getRequestList 实时统计 | 小 | UI 与核心对齐 |
| **P2** | 核心日志落盘 | 小 | 崩溃复盘 |
| **P2** | 订阅自动更新 worker | 中 | 完成字段语义 |
| **P2** | i18n 补全 | 中 | 多语言体验 |
| **P2** | onAuthorizationResult 授权 UX | 小 | 授权反馈 |
| **P3** | 品牌统一 | 中 | 品牌一致性 |
| **P3** | Canvas 自适应 | 小 | 视觉 |
| **P3** | 单测 + Lint | 中 | 质量安全网 |

---

## 5. 一句话总结

**三轮审查共确认 45 项发现**（P0×6 / P1×11 / P2×16 / P3×15，其中 2 项自我修正、1 项 M3 判断不准确被修正），**核心结论**：
- **架构**：双进程 + LocalSocket 设计正确（真机验证），但"UI 进程直接 import libflclash.so"是最大架构债务（P1-1）
- **最紧急**：测速卡死（P0-1~3，根因=超时矛盾 + toast 轰炸，本轮最终定位）
- **最隐蔽**：VPN 假连接（P0-4，官方文档确认系统不通知 UI，需自建心跳）
- **三轮互补性**：M3 强于工程/配置/Go 侧静态分析，K3 强于运行时/真机/超时类问题——**融合后无盲区**
