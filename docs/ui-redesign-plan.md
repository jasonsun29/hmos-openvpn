# UI 2.0 改版规划：HarmonyOS 原生质感（2026-08-15）

> 方向：毛玻璃卡片 / 系统级动效 / 圆润留白，像系统自带应用一样精致。
> 范围：全部 8 页 + 服务卡片完整改版；**功能零回归**（全局模式三点硬性需求、离线选端点、订阅导入导出、二维码、服务卡片、主题色自定义等全部保留）。

## 0. 现状基线（改版前）

- 复刻 Clash Verge 的 iOS 风：亮色 `#007AFF` / 暗色 `#0A84FF`，浅灰背景 + 12vp 圆角卡片
- 导航 = emoji 图标（✈ 🛰 等）+ 文字；间距紧凑；组件基本是裸 ArkUI 默认样式
- 已具备：Navigation 双态（展开态 180vp 侧栏 / 折叠态 64vp 图标栏）、暗色模式、主题色 10 色板、Canvas 流量图、bindSheet

## 1. 设计系统（Phase A，一次定义全项目复用）

### 1.1 色彩（Theme.ets 重构，不删现有 API）
- **强调色**：保留用户自选主题色（10 色板），作为 App 主色
- **分层背景**：页面底 = 系统分层色思路——亮色 `#F2F3F5` 底 + 白色卡片；暗色 `#1C1C1E` 底 + `#2C2C2E` 卡片
- **玻璃卡片**：`rgba(255,255,255,0.72)`（亮）/ `rgba(44,44,46,0.72)`（暗）+ backgroundBlurStyle
- **语义色**：成功 #34C759 / 警告 #FF9F0A / 危险 #FF453A / 信息主题色（HarmonyOS 语义色系）
- **文字**：主 #1F1F1F（亮）/ #F5F5F7（暗），次级 #8E8E93

### 1.2 形状与间距（tokens 进 Theme.ets）
- 卡片圆角：20vp（大卡）/ 16vp（行卡片）；胶囊 = 圆角/2
- 页面留白：16vp 边距；卡片内 padding 16vp；元素间距 8/12/16 三级
- 侧栏：展开 180vp / 折叠 64vp（不变）；导航项 48vp 高、圆角 14vp、选中态 = 主题色 10% 底色 + 主题色图标/文字

### 1.3 图标体系（新建 model/Symbols.ets）
- **SymbolGlyph 全面替代 emoji**（体积小、可着色、随主题变色、动效支持，API 11+ 可用）；**用户明确要求：页面不再出现任何 emoji**
- 资源名已从官方 SDK 符号表（id_defined.json，4032 个）逐一核实存在性，映射（AppIcon 组件 switch 显式映射，$r 需字面量）：
  - 导航：首页 `house`/`house_fill`、代理 `square_grid_2x2`、订阅 `square_stack_3d`、
    设置 `gearshape`、连接 `arrow_left_arrow_right`、规则 `list_number`、
    日志 `doc`、解锁 `film`；Logo 区 `paperplane`
  - 组类型：Selector `shuffle`、URLTest `bolt`、Fallback `arrowshape_down_to_line`、
    LoadBalance `split`、Relay `link`、默认 `archivebox`
  - 状态：选中 `checkmark`、成功 `checkmark_circle_fill`、失败/不可用 `xmark_circle_fill`、
    警告 `warning`、展开 `chevron_right`/`chevron_down`、测速 `bolt`、扫描 `qrcode`、
    编辑 `square_and_pencil`、导出 `upload`、删除 `trash`
- 构建期逐个验证 symbol 资源名（无效名编译报错，迭代替换）

### 1.4 动效规范
- 页面元素进场：`animateTo({ curve: curves.springMotion(0.4, 0.7), duration: 350 })` 统一封装
- 组展开/收起：springMotion + 高度过渡
- 卡片按压：scale 0.98（`stateEffect` 或 transition 统一实现）
- Toggle/开关：系统组件默认动效

### 1.5 通用组件（新建 components/ 目录）
- `GlassCard`：毛玻璃容器（backgroundBlurStyle + 半透明底色 + 20vp 圆角 + 可选按压反馈）
- `SectionHeader`：分组标题（主题色小圆点 + 标题 + 可选右侧动作）
- `StatusChip`：状态胶囊（✅/❌/⚠️/检测中，语义色）
- `PrimaryButton` / `GhostButton`：胶囊主按钮 / 描边次按钮

## 2. 分页改版清单

### Home（首页）
- 顶部大标题"首页"（28fp 粗体）
- **Hero 状态卡**：玻璃大卡——VPN 状态（大字"已连接/未连接"）+ 状态点 + 大号系统 Toggle + 当前代理副标题
- 模式选择：胶囊分段控件（规则/全局/直连，选中白底投影，替代裸 Text 按钮）
- 流量卡：实时波形（Canvas 保留）+ ↑↓ 速率 + 累计，玻璃化
- 工具行：当前代理 / 本地出口 IP / 连通性测试 → 三张小玻璃卡（图标+文案+箭头）

### Proxies（代理）
- 顶部：模式指示胶囊（全局/规则/直连）+ 在线状态点；"全部测速/刷新"胶囊按钮
- 组卡片：玻璃行卡片；展开态端点行 = 圆形选中指示 + 延迟胶囊徽章（绿 <300 / 橙 <800 / 灰超时）
- 离线横幅：琥珀色小胶囊 + 图标

### Profiles（订阅）
- 订阅卡：名称 + 用量进度条（已用/总量）+ 到期倒计时胶囊；激活 ✓ 徽章
- 行内操作图标化（SymbolGlyph：编辑=square.and.pencil、二维码=qrcode、导出=arrow.up.doc、删除=trash）
- 编辑/QR Sheet：原生 Sheet + 玻璃头部
- 导入输入行：玻璃搜索框样式

### Settings（设置）
- 分组玻璃卡：外观（主题模式分段控件 + 10 色板圆点选择器）、网络（端口/DNS/TUN 分段）、GeoX 数据（上次更新 + 更新胶囊按钮）、诊断（导出）
- 色板选中态：白圈描边 + 主题色对勾

### Connections（连接）
- 顶部汇总卡：连接数大数字 + ↑↓ 流量
- 连接行：host 主文字 + 规则/链路副文字 + 时长/流量右对齐胶囊
- 搜索框玻璃化；全部断开 = 危险色描边按钮

### Rules（规则）
- 统计卡：总规则数 + DIRECT×n 徽章
- 规则行：序号 mono + 规则文本 + 命中计数胶囊

### Logs（日志）
- 日志卡：级别色点（info 蓝/warn 橙/error 红）+ 时间 mono + 消息
- 级别过滤 = 胶囊 Tab；清空按钮

### Unlock（解锁）
- 服务行玻璃卡：服务名 + 状态胶囊（✅ 解锁 / ❌ 不可用 / ⚠️ 失败 + HTTP 码）
- 全部检测 = 主色胶囊按钮；检测中 = LoadingProgress 动效

### 服务卡片（VpnCard）
- 玻璃底 + 状态点 + 模式副标题；与主 App 同设计语言

## 3. 实施顺序与验收

| Phase | 内容 | 验收 |
|---|---|---|
| A | 设计系统（Theme tokens + 通用组件 + SymbolGlyph 映射） | 构建过、lint 0 |
| B | MainPage 导航框架（玻璃侧栏 + 新图标 + 动效） | 模拟器双态截图对比 |
| C | Home | 布局 dump 核对 |
| D | Proxies / Profiles | 同上 |
| E | Settings / Connections | 同上 |
| F | Rules / Logs / Unlock | 同上 |
| G | 服务卡片 | 桌面卡片渲染 |
| H | 模拟器双态 + 真机回归 | 全部功能回归 + 三硬性需求复验 |
| I | 文档更新 + 提交 | git 分 phase 提交 |

## 4. 风险与对策

- **SymbolGlyph 资源名不确定** → 构建期验证，无效名替换（备选：保留 emoji）
- **backgroundBlurStyle 性能**（折叠屏大面积模糊）→ 仅卡片级使用，避免整页 backdrop
- **ArkTS 限制**（无 spread/解构）→ tokens 用 class getter，不复制对象
- **功能回归** → 每 phase 模拟器快速回归；改版不动数据层/服务层，只动 UI 层文件
- **折叠态 64vp 侧栏放不下 SymbolGlyph+文字** → 折叠态仅图标（现状即此），展开态图标+文字
