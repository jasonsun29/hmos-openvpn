# hmos-openvpn 权限矩阵文档（M0a-1 交付物）

> 日期：2026-08-11　依据：ClashBox（⭐4.2k，已侧载跑通的参照实现）实测源码 + 鸿蒙官方文档
> 状态：✅ 权限清单已确认（ClashBox 实证），待真机实测补 hdc 清单

---

## 一、结论先行

**VpnExtensionAbility 侧载运行不需要受限权限 `ohos.permission.MANAGE_VPN`。**
ClashBox 以 `type: "vpn"` 扩展能力 + 普通权限（INTERNET/KEEP_BACKGROUND_RUNNING）就实现了完整 VPN 代理，系统通过**运行时授权弹窗**（用户点击"允许"）授予 VPN 能力。这闭合了设计文档 R1 评审的 🔴 一票否决阻断项。

---

## 二、权限清单（对照 ClashBox 实测 module.json5）

| 权限 | 是否必需 | 用途 | 获取方式 |
|---|---|---|---|
| `ohos.permission.INTERNET` | ✅ 必需 | 网络访问 | 普通权限，声明即得 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | ✅ 必需 | 后台长时运行 | 普通权限，声明即得 |
| `backgroundModes: ["dataTransfer","taskKeeping"]` | ✅ 必需 | 长时任务声明（数据传输/任务保持） | module.json5 声明 |
| `ohos.permission.VIBRATE` | ⭕ 可选 | 振动反馈 | 普通权限 |
| `ohos.permission.LOCATION` | ⭕ 可选 | ClashBox UI 特定功能 | 运行时授权 |
| `ohos.permission.SET_WINDOW_TRANSPARENT` | ⭕ 可选 | PC 窗口透明 | 普通权限 |
| `ohos.permission.MANAGE_VPN` | ❌ 不需要 | — | 受限权限，**不申请**（ClashBox 实证） |

## 三、组件声明模板（对照 ClashBox）

```json5
// module.json5
"abilities": [{
  "name": "EntryAbility",
  ...
  "backgroundModes": ["dataTransfer", "taskKeeping"]
}],
"extensionAbilities": [{
  "name": "ClashVpnAbility",
  "srcEntry": "./ets/entryability/ClashVpnAbility.ets",
  "type": "vpn"
}],
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" },
  { "name": "ohos.permission.VIBRATE" }
]
```

## 四、VpnExtensionAbility 生命周期（ClashBox 实现）

- `onCreate(want)`：从 `want.parameters` 读核心类型和 requestId → 启动 `SocketStubService`（proxy_core 的 ArkTS 服务，内部调 NAPI startTun）→ 写 `vpn_ipc.lock` 锁文件（IPC 约定）
- `onDestroy()`：`stopVpn()` → 删除锁文件
- **同进程模型实证**：VPN 侧与 UI 侧通过同一 `filesDir` 的锁文件协调，非跨进程 fd 传递（与设计文档 §3.1 一致）

## 五、签名路径（自用侧载）

- 华为开发者账号已登录（Jas****）
- 签名材料：`devecocli signature generate` 自动生成（调试 profile + 证书 + 自动写入工程配置）
- 自用侧载无需企业认证；如需更高签名等级（系统级权限）才需受限权限申请——本项目不需要

## 六、待真机实测的 hdc 清单（M0a 实测时补全）

| 项目 | 命令 | 预期 |
|---|---|---|
| 安装 HAP | `hdc install <app.hap>` | success |
| 确认应用安装 | `hdc shell bm dump -n <bundle>` | 权限列表出现 |
| 触发 VPN 授权弹窗 | 启动应用→开启 VPN 按钮 | 系统弹窗"允许连接VPN" |
| 验证 VPN 已建立 | `hdc shell hidumper -s 1402` 或 `ifconfig` 查 tun 接口 | 出现 tun 接口 |
| 查看运行日志 | `hdc shell hilog | grep ClashBox` | 无 panic |

---

## 结论

M0a-1 权限矩阵**已闭合**：权限清单 = INTERNET + KEEP_BACKGROUND_RUNNING + backgroundModes(dataTransfer/taskKeeping)，无需受限权限。剩余工作为工程骨架搭好后跑 hdc 实测清单验证。
