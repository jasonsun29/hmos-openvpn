# P3 阶段实施计划（15 项）

> 生成时间：2026-08-14。P0/P1/P2 共 33 项已完成，本文档为剩余 P3 全部 15 项的具体改动方案。
> 约束延续：**不重编译 Go**，全部改动限 ArkTS/ets/json5/shell 脚本层。
>
> **进度（2026-08-15）**：**P3 全部 15 项 + 全局模式重构完成**。第一批 ✅（t32/t30/t31/t34/t35）、第二批 ✅（t36/t40/t37）、第三批 ✅（t38/t39/t41/t42）、第四批 ✅（t43/t33/t44：release 构建分支 / bindSheet 对话框 / Navigation 迁移）。全局模式重构（离线选端点 + 默认全局 + 订阅解耦映射，替代 yaml 补丁方案）代码层验证通过。
>
> **模拟器验证完成（2026-08-15，commit dfef35b）**：UI 层 19 项全过（详见 docs/AGENT_CONTEXT.md「模拟器验证」章节），顺带修复 10 个真 bug（启动模式恢复缺失 / bindSheet 覆盖 / 轮询泄漏 / [object Object] / 表单索引等）。**剩余唯一待办：真机回归**（全局模式重构 + 第四批 + 模拟器修复项真机复验 + QR 生成 + VPN 授权流程，待设备连接）。

---

## t30 P3-1 Canvas 尺寸 onAreaChange 自适应

**文件**：`entry/src/main/ets/pages/Home.ets`

**现状**：`Canvas(this.canvasCtx).width(340).height(90)` 写死，`drawTrafficGraph()` 内 `w=340 / h=90` 常量写死（L253-256）。不同屏幕宽度下波形图宽度不随容器变化。

**改动**：
1. 加状态：`@State canvasW: number = 340; @State canvasH: number = 90;`
2. Canvas 组件加：
   ```typescript
   Canvas(this.canvasCtx)
     .width('100%')
     .height(90)
     .onAreaChange((_old: Area, newArea: Area) => {
       this.canvasW = Number(newArea.width);
       this.canvasH = Number(newArea.height);
       this.drawTrafficGraph();
     })
   ```
3. `drawTrafficGraph()` 中 `w = this.canvasW`，`h = this.canvasH`；网格线循环 `i < 4` 可改为 `Math.floor(h / 20)` 动态行数。
4. `step = w / 60` 保持不变（60 点满窗）。

**风险**：低。注意 onAreaChange 可能在 onReady 前触发，`drawTrafficGraph` 开头已有 `if (!ctx) return` 保护；history 为空时 `if (n < 2) return` 已有保护。

---

## t31 P3-2 流量波形 shift() 改为环形缓冲区

**文件**：`entry/src/main/ets/pages/Home.ets`

**现状**：L239-244 每次轮询 `downHistory.push()` + 超 60 点后 `shift()`。`shift()` 是 O(n)（每次移动 59 个元素），虽然 1Hz 频率下开销可忽略，但属于"每次采样全量搬移"的反模式。

**改动**（推荐最小侵入版：批量裁剪替代逐个 shift）：
1. 加常量：`private static readonly MAX_HISTORY_POINTS = 60;`
2. 采样处改为：
   ```typescript
   this.downHistory.push(this.downRate);
   this.upHistory.push(this.upRate);
   if (this.downHistory.length > HomePage.MAX_HISTORY_POINTS * 2) {
     // 批量裁剪：摊还 O(1)，避免每秒 shift 全量搬移
     this.downHistory.splice(0, this.downHistory.length - HomePage.MAX_HISTORY_POINTS);
     this.upHistory.splice(0, this.upHistory.length - HomePage.MAX_HISTORY_POINTS);
   }
   ```
   （保留 push 追加语义，drawTrafficGraph 的遍历逻辑无需改。）

**备选方案**（完整环形缓冲区）：head 索引 + 固定长度数组 + 读取时按 (head - n + max) % max 顺序遍历。收益更大但读取逻辑易错；若采用，建议把 `pushWindow / readWindow` 抽成纯函数并补单测。

**风险**：低（方案 A）/ 中（方案 B，需要单测覆盖）。

---

## t32 P3-3 formatBytes 公共化（去 3 处重复）

**文件**：`Home.ets` / `Connections.ets` / `Profiles.ets`（改）；`AppService.ets`（已是公共实现）

**现状**：`AppService.formatBytes`（static，L245）已存在且 `BackgroundKeepAliveService` 已在用；但 `Home.formatBytes`（L368）、`Connections.formatBytes`（L75）、`Profiles.formatBytes`（L302）三处仍各自复制了一份实例方法。

**改动**：
1. 删除三处实例方法；
2. 调用点改 `AppService.formatBytes(...)`（或 `this.appService` 处已有实例直接用）；
3. `Home.formatRate` 保留（它组合 formatBytes 追加 `/s`），内部改为调 `AppService.formatBytes`。

**风险**：低，纯删重。注意 `Profiles.formatUsage` 也依赖 `this.formatBytes`，一并替换。

---

## t33 P3-4 Profiles 编辑对话框改 CustomDialog / bindSheet

**文件**：`entry/src/main/ets/pages/Profiles.ets`

**现状**：L179-216 用 `if (this.showEditor) { Column() {...}.position({x:'5%', y:'10%'}).zIndex(10) }` 手写覆盖层模拟对话框，存在层级遮挡、无法系统级动画、返回键不关闭等问题。

**改动**（推荐 bindSheet，HarmonyOS NEXT 首选）：
1. 定义独立组件：
   ```typescript
   @Component
   export struct ConfigEditorSheet {
     @Link content: string;
     onSave: (s: string) => void = () => {};
     build() {
       Column() {
         Text('编辑配置') ...
         TextArea({ text: this.content }).height('60%')...
         Button('保存配置').onClick(() => { this.onSave(this.content); })
       }
     }
   }
   ```
2. ProfilesPage 中：
   ```typescript
   @State showEditor: boolean = false;
   ...
   .bindSheet($$this.showEditor, this.editorSheet(), { height: '70%', showClose: true })
   ```
3. `editProfile` 读配置后 `this.editContent = content; this.showEditor = true;`
4. `saveEdit` 逻辑保持不变（保存后 `this.showEditor = false`）。
5. 删除旧覆盖层 UI 和 `zIndex(10)`。

**备选**：`@CustomDialog` + `CustomDialogController`（若 bindSheet 在当前 API 版本不可用）。

**风险**：中。bindSheet 需要 API 12+；页面内 `@Consume colors` 在 sheet 内依然可用（提供者 MainPage）。

---

## t34 P3-5 tryRunAsync 工具 + 统一错误处理

**文件**：新建 `entry/src/main/ets/utils/AsyncUtils.ets`；渐进替换各页

**现状**：`try { await x } catch (e) { console.error(tag, msg) }` 模式全工程 30+ 处（REVIEW 2.3）。

**改动**：
1. 新建工具：
   ```typescript
   export async function tryRunAsync<T>(tag: string, fn: () => Promise<T>): Promise<T | undefined> {
     try {
       return await fn();
     } catch (e) {
       const msg: string = (e instanceof Error) ? e.message : String(e);
       console.error(tag, msg);
       return undefined;
     }
   }
   ```
2. 渐进替换：优先替换 `AppService` / `Home` / `Proxies` 里的高频 catch 块：
   ```typescript
   // 旧
   try { await svc.loadConfig(params); } catch (e) { console.error('Home', String(e)); }
   // 新
   await tryRunAsync('Home', async () => { await svc.loadConfig(params); });
   ```
3. **不强制一次全量替换**（降低 diff 风险），新代码一律使用该工具。

**风险**：低。纯新增工具 + 可选替换。

---

## t35 P3-6 Connections 页搜索/过滤

**文件**：`entry/src/main/ets/pages/Connections.ets`

**改动**：
1. 加状态：`@State searchText: string = '';`
2. 标题行下加搜索框：
   ```typescript
   TextInput({ placeholder: '搜索 host / 规则', text: this.searchText })
     .width('92%').height(36).margin({ bottom: 8 })
     .onChange((v: string) => { this.searchText = v; })
   ```
3. 列表渲染前过滤：
   ```typescript
   private filtered(): Array<ConnectionInfo> {
     if (this.searchText === '') return this.connections;
     const kw = this.searchText.toLowerCase();
     return this.connections.filter((c: ConnectionInfo) =>
       this.hostOf(c).toLowerCase().includes(kw) ||
       (c.rule ?? '').toLowerCase().includes(kw));
   }
   ```
4. `ForEach(this.filtered(), ...)` 替换 `ForEach(this.connections, ...)`；空状态文案区分"无连接"与"无匹配结果"。

**风险**：低。注意 ForEach 的 key 生成器 `(c) => c.id` 不变，过滤后 key 仍唯一。

---

## t36 P3-7 本地文件订阅导入 @ohos.file.picker

**文件**：`entry/src/main/ets/pages/Profiles.ets`（主）；`proxy_core/src/main/ets/Profile.ets`（已有 `saveByUri`）

**现状**：REVIEW 3.7——`ProfileType.File` 枚举已定义，但 UI 只有 URL 导入。

**改动**：
1. import：`import { picker } from '@kit.CoreFileKit';`
2. 加"从文件导入"按钮 + 方法：
   ```typescript
   async importFromFile(): Promise<void> {
     const context = getContext(this) as common.UIAbilityContext;
     const docPicker = new picker.DocumentViewPicker(context);
     try {
       const uris = await docPicker.select({
         maxSelectNumber: 1,
         fileSuffixFilters: ['.yaml', '.yml']
       });
       if (uris.length === 0) return;
       const profile = new Profile(ProfileType.File, '');
       profile.loadContext(context);
       await profile.saveByUri(uris[0]);
       const repo = this.appService.getProfileRepo();
       if (repo) {
         await repo.addOrUpdate(profile);
         promptAction.showToast({ message: '文件导入成功' });
         await this.loadProfiles();
       }
     } catch (e) {
       promptAction.showToast({ message: '导入失败: ' + String(e) });
     }
   }
   ```
3. `Profile.saveByUri` 已实现（copy uri → getProfilePath），无需改 proxy_core。
4. **权限**：picker 走系统文件访问框架，`module.json5` 无需新增权限。

**风险**：低-中。DocumentViewPicker.select 的返回类型在不同 API 版本有差异（uri 数组 vs 字符串），以实际 IDE 提示为准。

---

## t37 P3-8 GeoX 自动更新 UI 入口

**文件**：`entry/src/main/ets/pages/Settings.ets`；`SocketProxyService.updateGeoData(name, type)` 已存在（REVIEW 3.6）

**改动**：
1. Settings 加"GeoX 数据"卡片：
   ```typescript
   ListItem() {
     Column({ space: 8 }) {
       Row() {
         Text('GeoX 数据').layoutWeight(1)
         Text(this.geoLastUpdate)   // 如 "3 天前"
         Button('更新').onClick(() => this.updateGeoData())
       }
     }
   }
   ```
2. 更新逻辑：
   ```typescript
   async updateGeoData(): Promise<void> {
     const svc = this.appService.getProxyService();
     if (!svc) { promptAction.showToast({ message: 'VPN 未启动' }); return; }
     try {
       // geoType 映射 defaultGeoXMap：geoip/geosite/asn/mmdb
       await svc.updateGeoData('geoip', 'metadb');
       await svc.updateGeoData('geoip', 'dat');
       await svc.updateGeoData('geosite', 'dat');
       await svc.updateGeoData('asn', 'mmdb');
       promptAction.showToast({ message: 'GeoX 更新完成' });
     } catch (e) { ... }
   }
   ```
3. **自动更新**：在 `GeoDataInstaller.install`（P2-1 已建）末尾加 7 天检查——`fileIo.statSync(geoPath)` 读 mtime，超过 7 天则下次 VPN 启动后自动触发（或只在 UI 打开 Settings 时提示"数据已过期"）。
4. **注意**：`updateGeoData` 是 IPC RPC，Go 端 `main_cgo.go` 已实现，VPN 必须已启动；UI 侧先判 `vpnOn`。

**风险**：中。需先确认 `updateGeoData(geoName, geoType)` 的参数语义（对照 `ClashConfig.ts` 的 `defaultGeoXMap` 键）。

---

## t38 P3-9 updateDns 删除或接进设置

**文件**：`entry/src/main/ets/entryability/ClashVpnAbility.ets`（若接入）；`proxy_core/src/flclash/main_cgo.go`（不重编译，仅记录）

**现状**：REVIEW 3.4——Go 端 `updateDns` NAPI 已实现（main_cgo.go L173），ArkTS 无调用方。

**决策建议**：**接进设置**（VPN 进程内 NAPI 可用，无需重编译 Go）：
1. `ClashVpnAbility.loadActiveConfig` 的 `setTunOptions()` 之后，调 `updateDns(['172.19.0.2'])` 把系统 DNS 指向 FakeIP 网关（增强 fake-ip 模式的 DNS 接管）。
2. `onDestroy()` 恢复：调 `updateDns([])` 或 Go 端默认恢复逻辑。
3. **前置条件**：先查 `libflclash.so` 对应的 `.d.ts` 声明（`proxy_core/src/main/cpp/types/libflclash/` 或 Index.d.ts），确认 `updateDns` 的 NAPI 导出签名（参数是 string[] 还是 JSON string）。

**备选**：若签名不匹配或行为未知——直接弃用：ArkTS 侧不调用，在 `.d.ts` 标注 `@deprecated 未接入，勿调用`。选择此路径时改动最小（仅注释）。

**风险**：高（接入）/ 低（弃用）。接入前必须实测：DNS 指向 FakeIP 网关后，普通直连流量是否受影响。

---

## t39 P3-10 UI 进程轻量保活

**文件**：`entry/src/main/ets/entryability/EntryAbility.ets`；`MainPage.ets`

**现状**：REVIEW 3.8——只有 VPN 进程有 BackgroundKeepAliveService 长时任务。

**改动**（推荐方案：UI 进程不单独保活，改做"状态恢复"）：
1. **理由**：HarmonyOS NEXT 对 UI 进程长时任务管控极严；且 VPN 扩展进程存活时，UI 被回收不影响隧道工作（Home 数据来自 IPC）。
2. `EntryAbility.onBackground`：不启动长时任务，仅 `AppService.getInstance().pingCoreNow()` 轻量验活。
3. `EntryAbility.onForeground` / `onNewWant`：调 `pingCoreNow()` + 恢复 AppStorage 状态（`vpnAlive` / `vpnOn` 重新从心跳结果推导）。
4. `MainPage.aboutToAppear`：加 `if (AppStorage.get('vpnOn')) { this.appService.pingCoreNow(); }`（已有类似逻辑在 Home.onPageShow，抽到 MainPage 更全面）。

**备选**（真·保活）：`backgroundTaskManager.startBackgroundRunning(context, ['dataTransfer'], wantAgent)` + 最小通知（复用 BackgroundKeepAliveService 但给 UI 进程用）。需要实测系统策略是否放行，收益有限。

**风险**：中。行为与系统策略相关，需真机验证。

---

## t40 P3-11 Profile 分享/导出

**文件**：`entry/src/main/ets/pages/Profiles.ets`

**现状**：REVIEW 3.10——无 toYaml/share 方法。

**改动**（推荐 picker.save 导出）：
1. 在订阅列表项的"删除/编辑"旁加"导出"按钮：
   ```typescript
   async exportProfile(p: Profile): Promise<void> {
     const context = getContext(this) as common.UIAbilityContext;
     const home = await getHome(context);
     const cfgPath = home + '/profiles/' + p.id + '/config.yaml';
     if (!(await fileExists(cfgPath))) { toast('配置不存在'); return; }
     const docPicker = new picker.DocumentViewPicker(context);
     const saveUri = await docPicker.save({
       newFileNames: [(p.name ?? p.id) + '.yaml']
     });
     // 复制 config.yaml 到 saveUri
     fileIo.copy(cfgPath, saveUri);
   }
   ```
2. **分享**（可选增强）：HarmonyOS 分享文件用 `systemShare`（API 18+）或 `want.parameters.fileUris`（受限）。第一版只做"导出到文件"，分享后续再迭代。
3. Profile 层不新增 toYaml()——config.yaml 已经在磁盘，直接 readText/copy 即可。

**风险**：中。DocumentViewPicker.save 的返回类型/参数在不同 API 版本有差异。

---

## t41 P3-12 扫码导入

**文件**：`entry/src/main/ets/pages/Profiles.ets`；`entry/src/main/module.json5`（若需 CAMERA 权限）

**现状**：REVIEW 3.11——无扫码能力。

**改动**：
1. **优先方案**（系统扫码 kit，无三方依赖）：
   ```typescript
   import { scanCore } from '@kit.CoreScanKit';
   // 启动扫码页，回调拿到结果字符串
   ```
   拿到 URL 后复用 `importFromUrl` 的校验+导入逻辑（抽公共方法 `doImportUrl(url: string)`）。
2. 校验：`https://` 开头才接受；扫码结果可能是 `clash://install?url=...` 等 schema，需解析出真实 URL。
3. **权限**：`module.json5` 加 `ohos.permission.CAMERA`（扫码需要相机预览）。若系统 kit 不可用，降级方案是引入 zxing 纯 JS 库（需要 OHPM 依赖，改动大）。
4. 用户拒绝相机权限时提示"可在设置中开启"。

**风险**：中-高。`@kit.CoreScanKit` 的 API 可用性需在新 IDE 验证（API 12+ 的系统扫码服务较新）；权限申请流程要走 `requestPermissionsFromUser`。

---

## t42 P3-13 EntryBackupAbility 实现

**文件**：
- `entry/src/main/ets/entrybackupability/EntryBackupAbility.ets`（主）
- `entry/src/main/resources/base/profile/backup_config.json`（配置）

**现状**：REVIEW 4.11——`EntryBackupAbility` 只有 hilog 占位；`module.json5` 已注册；`backup_config.json` 内容待确认。

**改动**：
1. **onBackup**：把关键数据复制到备份目录：
   ```typescript
   async onBackup() {
     // this.context 是 BackupExtensionContext，有 backupDir
     // 关键数据：
     //   1) RDB: filesDir/fsclash.db（+ -wal / -shm 若存在）
     //   2) active_profile.id
     //   3) profiles/ 目录（yaml 配置）
     // 用 fileIo.copyDir 或逐文件 copy 到 backupDir
   }
   ```
2. **onRestore**：从备份目录读回，覆盖 filesDir 对应路径；恢复后 AppService 无需重启（RDB 下次 init 读到新数据）。
3. **backup_config.json**：配置 include/exclude 规则，排除临时文件（temp_provider、cache 等）。
4. 注意 BackupExtensionAbility 的 context 类型与普通 Ability 不同，文件路径 API 需用 `BackupExtensionContext` 提供的方法。

**风险**：中。备份/恢复 API 较新，需在新 IDE 按 API 版本确认 `backupDir` 等成员可用性；写出的文件要完整测试"备份 → 卸载 → 恢复"闭环。

---

## t43 P3-14 release 分支剥离调试符号

**文件**：`proxy_core/src/flclash/build.sh`

**现状**：REVIEW 4.2——build.sh 固定 `-gcflags="all=-N -l"`（关优化 + 保留调试符号），无 release 分支。发布包 .so 又大又慢。

**改动**：
1. build.sh 加模式参数：
   ```bash
   MODE="${1:-debug}"   # debug | release
   if [ "$MODE" = "release" ]; then
     GCFLAGS=""
     LDFLAGS='-ldflags="-s -w" -trimpath'
   else
     GCFLAGS='-gcflags="all=-N -l"'
     LDFLAGS=""
   fi
   "$GO_OHOS" build -buildmode c-shared -tags "ohos with_gvisor" $GCFLAGS $LDFLAGS -o "$OUTPUT" .
   ```
2. 使用方式：`./build.sh debug`（开发，保留符号可调试） / `./build.sh release`（发布，剥离符号+优化）。
3. 配套：`proxy_core/build-profile.json5` 已配置 `nativeLib.debugSymbol.strip = true`（release 构建时 hvigor 会再剥一层），两处不冲突。
4. **本次不实际执行**（遵守不重编译 Go 约束），只改脚本；下次编译时生效。

**风险**：低。纯脚本改动，需在下次真正编译时验证 `-s -w` 不影响 NAPI 符号导出（c-shared 模式的导出表由 cgo 控制，`-s -w` 只影响 Go 符号表，理论安全）。

---

## t44 P3-15 Navigation / NavDestination 迁移

**文件**：`entry/src/main/ets/pages/MainPage.ets`（主）；7 个页面组件（轻改）

**现状**：`MainPage` 用 `currentIndex` + if/else 条件渲染切换页面。问题：切页即销毁重建（Home 的轮询 timer、Proxies 的滚动位置、Connections 的搜索词全部丢失），无转场动画，无路由栈。

**改动**：
1. MainPage 引入路由栈：
   ```typescript
   @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
   Navigation(this.pathStack) {
     // 侧栏 + 默认页
   }
   .mode(NavigationMode.Split)
   .navDestination(this.pageMap)
   ```
2. 页面映射：`@Builder pageMap(name: string) { if (name === 'Home') { NavDestination() { HomePage() }.title('Home') } ... }`
3. 侧栏点击改 `this.pathStack.pushPathByName('Home', null)`（或 replacePathByName）。
4. 各页面**组件代码不变**（HomePage 等仍可直接嵌入 NavDestination）；`@Consume colors` 链保持（MainPage @Provide 不变）。
5. **验证重点**（迁移后必须回归）：
   - Home 的 `onPageShow/onPageHide` 在 NavDestination 下是否仍触发（P1-11 退后台刷新逻辑依赖）；若行为变化，改用 NavDestination 的 `onShown/onHidden`。
   - AboutToAppear 只触发一次后，切页回来数据是否过期——需要把 `refresh()` 从 aboutToAppear 移到 onShown。

**风险**：中-高。生命周期语义变化是本项最大坑，P1-11 / P2-3 的定时器清理（aboutToDisappear）需逐一验证。

---

## 执行顺序建议

| 批次 | 项 | 理由 |
|------|-----|------|
| 第一批（低风险收尾） | t32 → t30 → t31 → t34 → t35 | 纯 UI 局部改动，可快速出成果 |
| 第二批（功能补齐） | t36 → t40 → t37 | 文件导入/导出/GeoX，均有现成底层 API |
| 第三批（需真机验证） | t38 → t39 → t41 → t42 | 依赖系统行为，需实测 |
| 第四批（工程收尾） | t33 → t43 → t44 | 对话框重构与 Navigation 迁移放最后，避免与其他项交互 |

## 切换 IDE 后首次开工 Checklist

1. `hvigorw assembleHap`（或 IDE Build）验证 P2 改动可编译
2. `hvigorw test` 跑新增 21 个单测 case
3. `./scripts/install-hooks.sh` 装 lint pre-commit（有 git 仓库时）
4. 检查 `local.properties` 证书路径与本机一致
5. 按上表第一批顺序开工
