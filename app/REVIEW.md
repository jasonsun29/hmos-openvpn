# hmos-openvpn 代码与架构评审

| 项目 | 值 |
|---|---|
| 仓库 | `/Users/jason/harmony-vpn/app` |
| 模块 | `entry`（ArkTS UI） + `proxy_core`（HAR 桥接层 + Go 内核） |
| 内核 | mihomo v1.17.1（MetaCubeX Clash Meta）+ 自定义桥接 |
| 构建 | DevEco Studio（Hvigor）+ `go-ohos` 交叉编译 `libflclash.so` |
| 评审视角 | HarmonyOS 应用工程最佳实践、跨进程架构、可维护性、发布质量 |
| 评审日期 | 2026-08-12 |

---

## 0. 项目概览

`hmos-openvpn` 是 HarmonyOS NEXT 上的代理客户端，对外称 "OpenVPN"，实际内核是 mihomo/Clash Meta。功能层面定位为 Clash Verge 的鸿蒙版（订阅、代理节点、规则、TUN 模式 VPN、流量/连接/日志）。

整体架构：

```
┌────────── UI 进程 (entry, UIAbility) ──────────┐
│ EntryAbility                                   │
│   └── pages/MainPage ─ 侧栏导航 ─┬─ Home        │
│                                    ├─ Proxies     │
│                                    ├─ Profiles    │
│                                    ├─ Settings    │
│                                    ├─ Connections │
│                                    ├─ Rules       │
│                                    └─ Logs        │
│                                                 │
│ AppService（单例门面）                          │
│   ├─ Preferences 持久化                          │
│   ├─ ProfileRepo（RDB: fsclash.db）            │
│   └─ SocketProxyService ── LocalSocket RPC ──┐  │
└─────────────────────────────────────────────────┘ │
                       ↓ LocalSocket（ClashBox.sock）↓
┌─── VPN 扩展进程 :vpn (ClashVpnAbility) ────┐
│ SocketStubService                          │
│   ├─ 监听 ClashBox.sock（UI 端 RPC）        │
│   └─ FlClashVpnService                     │
│        ├─ startVpn → vpnExtension.VpnConnection → tunFd
│        ├─ LocalSocket(/clash_go.sock) 给 Go 核心送 startClash/tunFd
│        └─ 设置 TUN 选项（tunIp/routeAddress/acceptList） │
│                                             │
│ libflclash.so ── NAPI 桥接 ──┐            │
│   (napi_init.cpp)              ↓            │
│ proxy_core/src/flclash/        │
│   (Go: hub.go + ipc.go + main_cgo.go + lib_linux.go) │
│     ├─ initClash / updateConfig / startTun / getVpnOptions …
│     ├─ startIpc 监听 /clash_go.sock        │
│     └─ 内嵌 mihomo 全部代码                 │
└─────────────────────────────────────────────┘
```

---

## 1. 架构层面（最严重）

### 1.1 跨进程通信存在"双通道并存"问题

**现象**：UI/ArkTS ↔ Go 同时存在两条调用通道。

| 通道 | 发起方 | 接收方 | 注册位置 |
|---|---|---|---|
| **NAPI** | `ClashVpnAbility` / `SocketProxyService` 直接 `import { ... } from 'libflclash.so'` | `libflclash.so` 的 `init()` 注册表 | `proxy_core/src/flclash/main_cgo.go` |
| **LocalSocket IPC** | `SocketProxyService` 通过 `ClashBox.sock` | Go 端 `startIpcProxy` 监听 `/clash_go.sock` | `proxy_core/src/flclash/ipc.go` |

同一种能力两边都暴露：`startClash/stopClash`、`getProxies`、`getConnections`、`getTraffic`、`changeProxy`、`getVpnOptions`、`updateConfig`/`Load` 等。

**问题**：
- 调用方需要"猜"走哪条：UI 进程混着用，`AppService.loadActiveProfile` 走 NAPI，Proxies 页面走 IPC 的 `queryProxyGroups`。
- 两份 `ClashRpcType` 枚举（`proxy_core/src/main/ets/rpc/IClashManager.ts` 第 8 行 vs `proxy_core/src/flclash/ipc.go` 第 63 行）必须手动保持一致，极易漂移。
- 调试时日志无法对应：同一行为可能从 `M0b3`、`T4`、`T5` 三个 tag 出现。

**建议**：
- 明确边界：**UI 进程 ↔ VPN 进程**走 IPC（LocalSocket，单一通道），**VPN 进程 ↔ Go 内核**走 NAPI（进程内同步/异步调用）。
- UI 永远不应该 `import from 'libflclash.so'`；`libflclash.so` 只在 VPN 进程里加载。

### 1.2 "激活订阅"的状态在四个地方同步

| 位置 | 形式 | 写入点 |
|---|---|---|
| `AppService` Prefs | `active_profile_id`（key=`app_settings`） | `AppService.setActiveProfileId` |
| VPN 进程文件 | `filesDir/active_profile.id` | 同上 |
| RDB | `Profile.id`（靠"全局唯一"的隐式约定，无 `active` 列） | `ProfileRepo.addOrUpdate` |
| Go 内核内存 | `state.CurrentState.CurrentProfileName`、`currentConfig` | `hub.go: handleUpdateConfig` |

`AppService.setActiveProfileId` 写完 Prefs 还要写文件 + 复制 yaml，而 `ClashVpnAbility.loadActiveConfig` 第 67-74 行**又复制了一次** yaml。这是典型的"每个调用方各自同步，行为不一致"。

```typescript
// AppService.setActiveProfileId 第 130-137 行
const srcPath = context.filesDir + '/ClashBox/profiles/' + id + '/config.yaml';
const dstPath = context.filesDir + '/ClashBox/profiles/' + id + '.yaml';
...
// ClashVpnAbility.loadActiveConfig 第 67-74 行
const goCfgPath = home + '/profiles/' + activeId + '.yaml';
const arkCfgPath = home + '/profiles/' + activeId + '/config.yaml';
if (!(await ClashVpnAbility.fileExists(goCfgPath)) && (await ClashVpnAbility.fileExists(arkCfgPath))) {
  ...
}
```

**建议**：
- 引入 `ActivationStore` 单例，所有读写只走一处，订阅变化时主动 push 给 VPN 进程。
- 取消 yaml 文件复制；直接通过 `updateConfig({ 'profile-id': id, config: cfg })` 把整份配置传过去（事实上 `updateConfig` 已经接受 JSON payload，复制文件没必要）。

### 1.3 VpnExtensionAbility 生命周期与 UI 耦合过紧

`ClashVpnAbility.onCreate` 同时干三件事：起 IPC、加配置、启 TUN。任何一步失败（VPN 授权被拒、内核加载失败）`currentConfig` 都不会就绪，下次重启又来一次。

更隐蔽的问题：**VPN 进程崩溃后 UI 端没有任何恢复机制**。`vpnState` 只在 Home 里通过 AppStorage 维护，没有 `onDisconnect` 回调把 `vpnOn` 复位为 `false`。用户看到 UI 一直显示"已连接"，但实际 VPN 早被系统干掉。

**建议**：
- 用鸿蒙的 `Connection` 监听 `vpnExtension` 状态变化。
- 加健康检查心跳（UI 进程 5s 一次 ping VPN 进程的 LocalSocket，3 次失败标记断连）。

### 1.4 数据模型双轨制

- `Profile.proxySelected: Map<string, string>` 存在 RDB（序列化到 JSON 字段 `proxySelected`）。
- `UpdateConfigParams.params['selected-map']: Record<string, string>` 走 IPC。
- Go 侧 `state.CurrentState` 也是字符串化的 JSON。

Map / Record / JSON 三种表示法换来换去，每次转换都有序列化成本，也容易漏字段。

**建议**：统一成 `Record<string, string>`，所有持久化都 JSON.stringify。

---

## 2. 代码层面

### 2.1 `AppService` 单一类承担过多职责（235 行）

| 职责 | 方法 |
|---|---|
| Preferences 读写 | `getPrefString` / `setPrefString` |
| 主题、语言管理 | `getThemeMode` / `setThemeMode` |
| 激活订阅持久化 + 文件同步 | `getActiveProfileId` / `setActiveProfileId` |
| GeoX 数据初始化 | `initGeoIp`（60+ 行） |
| 诊断日志导出 | `exportLogs` |
| 文件读写工具 | `readFile` / `writeFile` / `fileExists` / `formatBytes` |

**建议**：拆成 `SettingsRepository`（Prefs）、`GeoDataInstaller`（GeoX 文件）、`DiagnosticCollector`（诊断导出）。

### 2.2 跨进程消息边界处理脆弱

`proxy_core/src/flclash/ipc.go` 的 `handleConnection`：

```go
buffer := make([]byte, 10240)
n, err := conn.Read(buffer)
...
err = json.Unmarshal(buffer[:n], &request)
```

只 `Read` 一次，假设一条消息一定 ≤ 10240 字节且一次性到达。LocalSocket 在负载高或消息体稍大（订阅配置 JSON 经常上 10KB）时会拆片，这条假设会丢消息。响应也是用 `EOF` 字符串拼的：

```go
conn.Write([]byte(string(res) + "EOF"))
```

调用方要 split `EOF` 才能解析。

**建议**：换成长度前缀（4 字节 big-endian + payload），或直接用 NDJSON（每条消息以 `\n` 结尾，Read 循环读取整行）。

### 2.3 错误处理风格不统一

```typescript
console.error('T5', 'loadActiveProfile failed: ' + msg);   // tag = 任务号
console.error('M0b3', '启用VPN失败: ' + msg);               // tag = 另一种
try { ... } catch (e) { /* ignore */ }                       // 静默吞
console.log('T1', 'AppService initialized');                 // console 而非 hilog
```

日志 tag `M0b3`、`T1`、`T2`、`T4`、`T5`、`T6`、`T7`、`T8`、`T9`、`T10`、`T11` 都是开发期任务编号，应该换成 `VPN.Core`、`Sub.Manager`、`Home.UI` 等语义化 tag。

**建议**：
- 全部走 `hilog`（鸿蒙官方），定义统一 tag 前缀。
- 建立 `tryRunAsync(fn, errorTag)` 工具函数，避免 catch 后只打日志不恢复。

### 2.4 资源泄漏

- `BackgroundKeepAliveService.stop` 重置 `notificationId` 为 `undefined`，但**没有删除对应通知**（`notificationManager.cancelNotification` 没调用）。
- `ClashVpnAbility.loadActiveConfig` 第 42-45 行 `fs.closeSync(file.fd)` 写法不一致：`fs.open` 返回的是 file object，标准用法是 `file.close()`，`closeSync` 接受的是数字 fd——类型不匹配。
- `SocketStubService.startService` 的 `server.listen` 失败时 `clientPool` 不会被清空，下次 startService 会泄露。

### 2.5 文件复制工具三处重复

- `AppService.ets`：`readFile` / `writeFile` / `fileExists`。
- `ClashVpnAbility.ets`：`static fileExists` / `readFile` / `writeFile`。
- `proxy_core/src/main/ets/fileUtils.ts`：`readFile` / `readFileUri` / `readText`（Index 里没 export）。

**建议**：统一到 `proxy_core/src/main/ets/fileUtils.ts` 通过 `proxy_core` 包导出。

### 2.6 硬编码路径散落

```typescript
const socketPath = this.vpnService.context.filesDir + '/ClashBox.sock'
const goPath = this.vpnService.context.filesDir + '/clash_go.sock'
const home = context?.filesDir + "/ClashBox"
const geoFiles: Array<string> = ['geoip.metadb', 'GeoIP.dat', 'GeoSite.dat', 'ASN.mmdb'];
```

**建议**：改成 `proxy_core/appPath.ts` 里的 `getHome` / `getSocketPath(name)` / `getGeoDataPath(name)`。

### 2.7 `Index.ets` 还在 `main_pages.json` 里

`pages/Index.ets` 是 M0b-1 阶段的 NAPI 验证页（"核心未加载"、"启动中..."），**发版时不应存在**。

```json
"src": ["pages/MainPage", "pages/Index"]
```

### 2.8 `Request.ts` 里的考古层

390 行里前 175 行全部是 `/* */` 注释掉的旧实现（`IpCountryList` / `ipInfoSources` / `CallIpResolver` / `checkIp`），后面才是新实现。`http` 和 `rcp` 两个网络包都 import 但只用 `http`。应该清掉。

---

## 3. 功能层面

对照代码里 `T1`～`T11` 任务号，目前**只是"任务名定义了，实现是半成品"**的功能：

### 3.1 订阅自动更新没有 worker

```typescript
// Profile.ets
autoUpdate: boolean = true
autoUpdateDuration: number = 60 * 1000 // 1 分钟
```

全代码找不到任何定时器或后台任务去触发"到达 autoUpdateDuration 时拉取订阅 URL"。`autoUpdateDuration` 字段是死的。

**建议**：在 `AppService` 或新加 `SubscriptionUpdater` 里 `setInterval`，到了时间调 `Profile.update()`。

### 3.2 TUN 重建逻辑缺失

`Settings.ets` 注释：

```
T6.3 DNS 配置（L3 变更：重建 TUN）
T6.4 TUN 栈（L3 变更：重建 TUN）
```

实际代码改 DNS / TUN 栈只是 `patchConfig` 走 `loadConfig` 下发配置，**没有 stopTun + startTun**。用户在设置里切了 fake-ip / gvisor stack，UI 改了但内核还在用旧 TUN——这是典型的"功能画了饼"。

**建议**：L3 变更要走 `clashStubService.stopVpn() → loadActiveConfig() → clashStubService.startVpn()`。

### 3.3 `TunStack` 枚举暴露但只实现了一种

`TunStack` 枚举定义有 `system` 和 `gvisor`，但 `tun.go` 只走 `sing_tun`（即 gvisor）。"system" 选项点了没效果。

**建议**：要么实现 system stack，要么把枚举里的 `system` 灰显/隐藏。

### 3.4 `updateDns` NAPI 暴露但 UI 没调用

`main_cgo.go` 第 173 行实现了 `updateDns`（更新系统 DNS 列表），但 ArkTS 侧没有调用方。`Settings.ets` 改 DNS 只是写到 ClashConfig 里推给核心，没有"替换系统 DNS"。

**建议**：要么删掉，要么真接进设置——开启 VPN 时把 `172.19.0.2` 推到系统 DNS，关闭时恢复。

### 3.5 `Rules` 页是"静态解析配置"

注释里说"mihomo 核心 NAPI 未暴露 /rules API，从配置解析展示（静态）"。

但 `getRequestList`（`ipc.go` 第 136 行 / `hub.go` 第 439 行 `reqeustList`）已经能拿到核心的请求列表，每条记录包含 `chains: []`（命中链）、`rule: string`（规则名）。完全可以用这个做"过去 N 秒内规则触发次数"的实时统计。

**建议**：改用 `getRequestList` 拉核心的 `statistic.Tracker`，统计 `rule` 字段频率，配合 `clearRequestList` 做时间窗统计。

### 3.6 GeoX 自动更新无 UI

`ClashConfig.ts` 第 21-26 行定义了 `defaultGeoXMap`（mmdb/asn/geoip/geosite 的官方下载地址），`main_cgo.go` 实现了 `updateGeoData(type, name)`。但**全代码找不到 UI 入口**——用户没法手动触发更新，也没法设置自动更新周期。

**建议**：在 Settings 加"更新 GeoX 数据"按钮；启动后检查 7 天前的 GeoX 文件自动触发。

### 3.7 导入本地文件订阅没有 UI

`ProfileType.File` 和 `ProfileType.External` 枚举定义了但只 `ProfileType.Url` 有 `importFromUrl` 实现。

**建议**：在 Profiles 页加"从文件导入"，用 `@ohos.file.picker` 选 `.yaml` / `.yml`。

### 3.8 进程级保活只有 VPN 进程

`BackgroundKeepAliveService` 只为 VPN 启动 long-time task。用户杀了 UI 进程后，VPN 进程一般会被一起回收（取决于系统策略）。UI 进程也需要轻量保活。

### 3.9 诊断导出太轻量

`AppService.exportLogs` 只导出 ArkTS 侧状态 + 文件存在性检查，没拉核心日志。Go 侧的 `log` 包走 `logrus`，但**没有把日志写到文件**——所有核心日志只通过 NAPI 的 `startLog` 回调传到 ArkTS，**没有持久化**。崩溃现场复盘时核心日志就没了。

**建议**：
- Go 侧写日志到 `filesDir/ClashBox/core.log`（带 rotate）。
- `exportLogs` 把这个文件一起打包。

### 3.10 没有"分享/导出配置"

`Profile.ets` 看不到 `toYaml()` 或 `share()` 方法。

### 3.11 没有"导入机场二维码"

Clash Verge 有"扫码导入"，本应用没看到 zbar/zxing 类的扫码能力集成。

---

## 4. 工程化层面

### 4.1 `build-profile.json5` 写死了证书绝对路径

```json
"certpath": "/Users/jason/.ohos/config/default_app_Fb9Tl5lx4X1L2-7u2wa5Z5iDLEWbSb6WJ2bbp9loA5Y=.cer",
"keyAlias": "debugKey",
...
```

这是**开发机本地路径**，换机器或换用户根本跑不起来。

**建议**：
- 把签名 material 路径挪到 `local.properties`（git ignored）。
- 或者在 `hvigorfile.ts` 里读环境变量。

### 4.2 调试符号没剥离

`proxy_core/src/flclash/build.sh`：

```
"$GO_OHOS" build -buildmode c-shared -tags "ohos with_gvisor" -gcflags="all=-N -l" ...
```

`-N -l` 关掉了优化。debug 构建没问题，但**没有 release 模式分支**。发布包带未优化 .so 既大又慢。

**建议**：分 `debug`/`release` 两套编译参数，release 用 `-trimpath -ldflags="-s -w"`。

### 4.3 混淆规则空跑

`entry/obfuscation-rules.txt` 和 `proxy_core/obfuscation-rules.txt` 都存在但没看到在 `build-profile.json5` 里启用 `"obfuscation": true` 或在 `hvigorfile.ts` 配 rules。

### 4.4 `@ohos.file.fs` vs `@kit.CoreFileKit` 不统一

同一项目混用两种文件 API：

- `AppService.ets` / `ClashVpnAbility.ets` / `Profiles.ets`：`import fs from '@ohos.file.fs'; fs.open / fs.read / fs.write`
- `Profile.ets`：`import { fileUri } from '@kit.CoreFileKit'`

`@kit.CoreFileKit` 是新版 kit API，`@ohos.file.fs` 是旧版。前者应统一替代后者。

### 4.5 国际化只完成一半

`en_US/element/string.json` 和 `zh_CN/element/string.json` 定义了 `nav_*` 键，但页面里**绝大多数还是硬编码中文**：

```typescript
promptAction.showToast({ message: '请先开启 VPN 再查看代理' });
promptAction.showToast({ message: '端口无效（1-65535）' });
promptAction.showToast({ message: '请输入订阅 URL' });
```

全部应该走 `$r('app.string.xxx')`。

### 4.6 没有单元测试

`proxy_core/src/ohosTest/` 存在但内容空（只有占位 `LocalUnit.test.ets` / `List.test.ets`）。

**建议**：把 `SubscriptionInfo.formHString`、`TrafficValue` 构造、`ProxyGroup` 解析这些纯函数先补单测；`ProfileRepo` 加集成测试。

### 4.7 没有 Lint 接入

`code-linter.json5` 存在但没看到 CI 集成。devEco CLI 的 `hvigor lint` 应该接进 pre-commit。

### 4.8 资源引用不一致

- `AppScope/resources/media/foreground.png` / `background.png` / `layered_image.json`
- `entry/src/main/resources/base/profile/` 自己的 `main_pages.json` / `backup_config.json`

启动图标 `startIcon` 在 entry 模块声明、应用图标在 AppScope 声明，分散了。`layered_image.json` 看起来是鸿蒙新版的分层图标，但 `startIcon` 还是旧的——**新版本应该全用 `layered_image.json`**。

### 4.9 应用名 / 包名 / 数据库名不统一

| 类别 | 名字 |
|---|---|
| 应用名（`EntryAbility_label`） | `OpenVPN` |
| 应用描述 | `hmos-openvpn` / `OpenVPN client for HarmonyOS` |
| 数据库名（`ProfileRepo.ts`） | `fsclash.db` |
| 工作目录（`getHome`） | `ClashBox/` |
| 工作目录（`appPath.ts`） | `ClashBox` |

三套名字（hmos-openvpn / fsclash / ClashBox）很可能 fork 自某个叫 "ClashBox" 或 "fsclash" 的旧项目。**品牌一致性需要重整**——应用商店描述、用户可见 UI、数据库/目录名要对齐。

### 4.10 没有隐私合规声明

鸿蒙应用商店上架要求必须声明：
- 收集哪些个人信息（IP 地址、订阅 URL 等）。
- 网络权限使用目的。
- 后台保活说明。

当前 `module.json5` 只声明了 `INTERNET` 和 `KEEP_BACKGROUND_RUNNING` 两个权限，没有 metadata 描述用途。

### 4.11 `EntryBackupAbility` 配了但没看到实现

`module.json5` 第 41 行注册了 `EntryBackupAbility`（backup 类型的 ExtensionAbility），指向 `ets/entrybackupability/EntryBackupAbility.ets`，但该文件没读，且 `backup_config.json` 配置项缺失。备份/恢复订阅配置是个不错的卖点但没做完。

---

## 5. 优先级路线图

| 优先级 | 项 | 工作量 | 收益 |
|---|---|---|---|
| **P0** | 统一双 IPC 通道（选 NAPI 或 IPC 一条） | 中 | 消除架构主矛盾 |
| **P0** | 把 `Index.ets` 从 `main_pages.json` 移除或删除 | 5 分钟 | 修复发版潜在崩溃 |
| **P0** | VPN 断连状态同步到 UI | 小 | 修复"假连接"显示 bug |
| **P0** | 签名 material 路径改成 env / `local.properties` | 小 | 跨机器可编译 |
| **P1** | `ActivationStore` 单例化，删掉 yaml 文件复制 | 中 | 消除同步漏洞 |
| **P1** | IPC 消息改成 length-prefix 帧 | 小 | 修复大配置丢消息 |
| **P1** | TUN 重建真的实现 | 小 | 让 DNS / TUN 栈设置生效 |
| **P1** | 订阅自动更新 worker | 中 | 完成 `Profile.autoUpdate` 语义 |
| **P2** | 拆 `AppService` 单一类 | 中 | 可维护性 |
| **P2** | 国际化补全（所有硬编码中文走 `$r`） | 中 | 多语言体验 |
| **P2** | Rules 页改成实时统计 | 小 | UI 与核心对齐 |
| **P2** | Go 侧核心日志落盘 | 小 | 崩溃复盘能力 |
| **P3** | GeoX 自动更新 UI | 小 | 数据时效性 |
| **P3** | 单测覆盖纯函数 | 中 | 重构安全网 |
| **P3** | 文件 API 统一到 `@kit.CoreFileKit` | 小 | 现代化 |

---

## 6. 一句话总结

架构上最大的问题是 **双 IPC 通道 + 多处状态同步**；代码上最大的问题是 **`AppService` 大类 + IPC 帧处理脆弱 + 文件工具三处复制**；功能上最大的问题是 **TUN 重建、自动更新、Rules 实时统计只画了饼没落地**；工程化上最大的问题是 **证书硬编码 + 国际化半成品 + 缺少单测 / Lint 接入**。