# hmos-openvpn

基于 HarmonyOS NEXT 的 VPN 客户端（Clash Verge 风格），UI 像素级复刻 [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) 交互，核心复用 ClashBox 的 `proxy_core`（mihomo 内核 → `libflclash.so` → NAPI）。

## 特性

- **双进程架构**：UI 进程 + `VpnExtensionAbility` 独立 VPN 进程（系统强制隔离），经 LocalSocket IPC 通信
- **三种代理模式**：规则 / 全局 / 直连，热切换
  - 全局模式 = 全部流量走所选端点；只有选"直连"才所有流量不走代理
  - 模式与节点选择跨重启持久化（`selected_map.json`）
- **离线可用**：未开 VPN 也可浏览/选择节点（本地解析订阅 yaml）；离线 TCP 探测测速
- **8 大页面**：首页（流量波形）/ 代理 / 订阅 / 设置 / 连接 / 规则 / 日志 / 解锁（流媒体检测）
- **订阅管理**：URL/文件/扫码导入，二维码分享（`clash://install`），自动更新与用量显示
- **UI 2.0**：HarmonyOS 原生质感——毛玻璃卡片、SymbolGlyph 系统图标、亮暗双主题、10 色主题色自定义、折叠屏双态布局（展开态侧栏 / 折叠态图标栏）
- **服务卡片**：桌面 2×2/2×4 卡片显示 VPN 状态，点击直达应用

## 技术栈

| 层 | 技术 |
|---|---|
| UI | ArkTS / ArkUI（Navigation + NavDestination，8 页面） |
| 核心 | mihomo（Clash Meta）编译为 `libflclash.so`，NAPI 桥接 |
| IPC | 双进程 LocalSocket（`clash_go.sock` RPC 29 种操作 / `ClashBox.sock`） |
| 数据 | RDB 订阅库 + 跨进程 JSON 状态文件 + Preferences |
| 工具链 | DevEco Studio 6.1.1 / HarmonyOS 6.1.1 (API 24) / hvigor |

## 构建

```bash
# 需 DevEco Studio 6.1.1+ 与 HarmonyOS SDK (API 24)
cd app
hvigorw build --mode module -p product=default -p buildMode=debug
# 或
devecocli build --build-mode debug
```

产物：`app/entry/build/default/outputs/default/entry-default-signed.hap`

> 签名：需在 DevEco Studio 中配置自动签名（Project Structure → Signing Configs）。本仓库不包含签名材料。

## 目录

```
app/
  entry/                  # UI 进程（8 页面 + VpnExtensionAbility + 服务卡片）
    src/main/ets/pages/   # 页面
    src/main/ets/components/  # UI 2.0 通用组件（GlassCard/AppIcon）
  proxy_core/             # 核心库（IPC/配置解析/订阅仓库）
    src/flclash/          # Go 核心编译脚本（build.sh）
docs/                     # 设计文档 / 上下文 / 审查报告
```

## 免责声明

本项目仅供学习与技术研究。使用代理访问被封锁内容请遵守当地法律法规；请勿用于非法用途。

## License

待定
