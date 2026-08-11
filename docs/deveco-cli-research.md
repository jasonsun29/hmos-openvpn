---

# 调研报告：macOS (Apple Silicon) 安装华为 DevEco Studio Command Line Tools

## 一、核心发现摘要

华为在 **HDC 2026** 期间正式发布了 **DevEco CLI**（`@deveco/deveco-cli`），这是一个通过 **npm** 分发的统一命令行工具，封装了 ohpm、hvigor、hdc、emulator、hilog 等完整工具链。**它可以独立于 DevEco Studio IDE 使用**，但底层仍需依赖 DevEco Studio 或 Command Line Tools 作为运行时/SDK 后端。

---

## 二、逐项回答

### 1) 官方下载页面和具体下载包名称

| 项目 | 地址 |
|------|------|
| **DevEco Studio 产品页** | https://developer.huawei.com/consumer/cn/deveco-studio/ |
| **下载中心（需登录）** | https://developer.huawei.com/consumer/cn/download/ |
| **DevEco CLI npm 包** | `npm install -g @deveco/deveco-cli@latest` |
| **DevEco Code npm 包** | `npm install -g @deveco/deveco-code@stable` |

**关键发现：**
- **下载任何官方二进制包（DevEco Studio DMG / Command Line Tools 压缩包）都需要华为账号登录**。点击"立即下载"按钮后会跳转到 `oauth-login.cloud.huawei.com` 登录页。
- 官方页面未公开直接下载链接（SPA 渲染，无静态 DMG URL）。
- DevEco CLI 本身通过 npm 安装，**不需要**华为账号即可 `npm install`。但首次使用 `devecocli` 的构建/运行等功能时需要登录（`devecocli auth login`）。
- **DevEco CLI 最新版本**：`1.2.2`（npm latest），`1.2.0-stable`（stable 标签）
- **DevEco Code 最新版本**：`0.1.7`（npm latest），`0.1.1-stable`（stable 标签）

> ⚠️ **不确定**：具体的下载包文件名未在公开页面暴露。根据历史经验，macOS 版通常命名为 `deveco-studio-mac-{version}.dmg` 或 `command-line-tools-mac-{version}.zip`，但当前版本（2026 年）的具体文件名需要登录后才能看到。

### 2) brew cask 或第三方镜像

| 渠道 | 结果 |
|------|------|
| **Homebrew** | ❌ 未找到任何 `deveco` 相关的 cask/formula |
| **GitHub 镜像** | ❌ 搜索 `deveco studio mirror` 无结果 |
| **ghfast 加速** | ❌ 未找到相关仓库 |
| **npm 淘宝镜像** | ✅ DevEco CLI 官方 README 提到可以使用 `https://registry.npmmirror.com/` |

> **结论**：目前没有 brew cask 或第三方镜像。DevEco CLI 的 npm 包可通过淘宝镜像加速，但 DevEco Studio / Command Line Tools 的二进制包只能从华为官方下载。

### 3) 环境变量配置

根据 DevEco CLI README 和 DevEco Code README，需要配置的环境变量如下：

| 环境变量 | 用途 | 示例值 |
|----------|------|--------|
| `DEVECO_CLI_STUDIO_PATH` | 指定 DevEco Studio 安装根目录（优先级最高） | `/Applications/DevEco-Studio.app` |
| `DEVECO_CLI_CLT_PATH` | 指定 Command Line Tools 安装根目录 | `/opt/command-line-tools` |
| `DEVECO_HOME` | DevEco Code 使用的 DevEco Studio 路径 | `/Applications/DevEco-Studio.app` |
| `DEVECO_CLI_DEBUG=1` | 调试模式，查看底层命令映射 | `1` |

**优先级链**：
```
DEVECO_CLI_STUDIO_PATH > DEVECO_CLI_CLT_PATH > Auto_Detect
```

**Auto_Detect 规则**：
- macOS 上自动检测 `/Applications` 或 `~/Applications` 下的 DevEco Studio 安装
- 找不到时 fallback 到 Command Line Tools

**PATH 自动处理**：DevEco CLI 安装后通过 npm 全局 bin 目录提供 `devecocli` 命令，内部自动调用 ohpm、hvigor、hdc 等工具，**无需手动将 hvigor/ohpm 加入 PATH**。

> ⚠️ **注意**：与 Android SDK 不同，目前 DevEco CLI 文档中**没有**提到 `DEVECO_SDK_HOME` 或 `HARMONYOS_SDK_HOME` 环境变量。SDK 路径由 DevEco CLI 根据 Studio/CLT 安装位置自动推断。

### 4) CLI 独立安装 HarmonyOS SDK 和首次构建是否需要登录

**SDK 管理能力**：
- DevEco CLI **依赖** DevEco Studio 或 Command Line Tools 作为 SDK 提供方，**不能完全独立下载 SDK**。
- 但 DevEco CLI 可以管理模拟器镜像：`devecocli emulator image download` 可下载模拟器系统镜像，首次使用需签署 HarmonyOS SDK 许可协议（`devecocli emulator license accept`）。
- 模拟器镜像下载和 SDK 许可协议接受可以**非交互式**完成（`emulator license accept`），适合 CI/自动化。

**首次构建是否需要登录**：
- DevEco CLI 提供 `devecocli auth login` 命令，会打开浏览器完成华为账号 OAuth 授权。
- README 明确说明"海外账户暂不支持"。
- 首次构建（`devecocli build`）**很可能需要登录**，因为需要访问 HarmonyOS SDK 和签名材料。
- DevEco CLI 支持自动生成调试签名：`devecocli signature generate`，可自动配置到项目 `build-profile.json5`。

### 5) macOS 从零到 `hvigorw assembleHap` 的完整步骤清单

> ⚠️ 以下步骤基于 DevEco CLI 官方文档，部分步骤（如下载 DevEco Studio）需要在浏览器中登录华为账号手动完成。

```bash
# ==========================================
# 步骤 1：安装 Node.js（>= 18，推荐 22+）
# ==========================================
# 如果已安装 nvm：
nvm install 22
nvm use 22

# 验证
node -v   # 应 >= 18
npm -v

# ==========================================
# 步骤 2：下载安装 DevEco Studio 或 Command Line Tools
# ==========================================
# 打开浏览器，登录华为账号后访问：
#   https://developer.huawei.com/consumer/cn/download/
# 下载 macOS (ARM) 版本的 DevEco Studio DMG
# 安装到 /Applications/DevEco-Studio.app

# 或者下载 Command Line Tools 压缩包（>= 26.0.0）
# 解压到 /opt/command-line-tools 或自定义路径

# ==========================================
# 步骤 3：安装 DevEco CLI
# ==========================================
npm install -g @deveco/deveco-cli@latest

# 验证安装
devecocli --version   # 应输出 1.2.2 或更高

# ==========================================
# 步骤 4：配置环境变量（可选，如果 Studio 不在默认位置）
# ==========================================
# 如果 DevEco Studio 安装在默认位置，可跳过
export DEVECO_CLI_STUDIO_PATH="/Applications/DevEco-Studio.app"

# 如果使用 Command Line Tools
export DEVECO_CLI_CLT_PATH="/opt/command-line-tools"

# 建议写入 ~/.zshrc
echo 'export DEVECO_CLI_STUDIO_PATH="/Applications/DevEco-Studio.app"' >> ~/.zshrc
source ~/.zshrc

# ==========================================
# 步骤 5：登录华为账号
# ==========================================
devecocli auth login
# 浏览器会打开华为账号登录页，完成授权
# 验证登录状态
devecocli auth status

# ==========================================
# 步骤 6：接受 SDK 许可协议（非交互式）
# ==========================================
devecocli emulator license accept

# ==========================================
# 步骤 7：创建 HarmonyOS 项目
# ==========================================
devecocli create --app-name MyApp --bundle-name com.example.myapp
cd MyApp

# ==========================================
# 步骤 8：构建项目（生成 .hap）
# ==========================================
devecocli build --build-mode debug

# 产物位置：
#   entry/build/default/outputs/default/entry-default-signed.hap
#   或 .app 文件（取决于构建参数）

# ==========================================
# 步骤 9（可选）：生成调试签名
# ==========================================
devecocli signature generate

# ==========================================
# 步骤 10（可选）：在模拟器上运行
# ==========================================
# 先下载模拟器镜像
devecocli emulator image download --device-type phone --os-version "HarmonyOS 5.0.0(12)"
# 创建并启动模拟器
devecocli emulator create MyPhone --device-type phone --os-version "HarmonyOS 5.0.0(12)"
devecocli emulator start MyPhone
# 运行应用
devecocli run --device MyPhone
```

---

## 三、关键来源链接

| 来源 | URL |
|------|-----|
| DevEco Studio 产品页 | https://developer.huawei.com/consumer/cn/deveco-studio/ |
| 下载中心（需登录） | https://developer.huawei.com/consumer/cn/download/ |
| DevEco CLI npm 包 | https://www.npmjs.com/package/@deveco/deveco-cli |
| DevEco Code npm 包 | https://www.npmjs.com/package/@deveco/deveco-code |
| DevEco Code GitHub（社区） | https://github.com/bbylw/DevEco-Code |
| DevEco CLI FAQ（GitCode） | https://gitcode.com/openharmony-sig/deveco-cli/wiki/FAQ.md |
| 命令行构建文档 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ide-command-line-building-app-V5 |

---

## 四、不确定/待验证项

1. **Command Line Tools 的具体下载包名称**：需要登录华为账号后才能看到，目前公开页面未暴露具体文件名。
2. **CLI 是否能完全脱离 DevEco Studio 下载 SDK**：官方文档说 CLI 依赖 Studio 或 CLT 作为 SDK 后端，但 CLI 的 `emulator image download` 命令暗示部分 SDK 管理能力。能否完全通过 CLI 管理 Native SDK/API 版本尚不确定。
3. **首次构建是否强制要求登录**：虽然 CLI 提供 `auth login` 且很多操作需要认证，但本地离线构建（仅 `devecocli build`）是否强制登录，文档未明确说明。建议假定需要登录。
4. **hvigorw 和 assembleHap 底层命令**：DevEco CLI 封装了 hvigor 构建，但直接使用 `hvigorw assembleHap` 需要手动配置环境。DevEco CLI 的 `devecocli build` 是推荐的替代方案。
5. **Linux 支持**：Linux 不支持 DevEco Studio（仅支持 Command Line Tools），但 CLI 本身支持 Linux。