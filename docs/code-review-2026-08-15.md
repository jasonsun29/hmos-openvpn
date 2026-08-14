# DevEco 代码审查与优化（2026-08-15）

> 工具：`devecocli check lint`（CodeLinter）+ ArkTS 编译告警。compat 检查需 Studio ≥26.0.0.810（本机 6.1.1.300，不可用，不升级——既定决策）。

## 审查前基线
- 编译告警 169 条；CodeLinter 6 条 warning / 0 error

## 修复项（已全部落地并通过模拟器冒烟）

### A. 弃用 API 迁移（-74 条告警，全部清除）
| 弃用 API | 新 API | 范围 |
|---|---|---|
| 全局 `getContext(this)` | `this.getUIContext().getHostContext()` | 10 个页面文件 22 处 |
| `promptAction.showToast` | `this.getUIContext().getPromptAction().showToast()` | 10 个页面文件 53 处 |
| `TextDecoder.decodeWithStream` | `decodeToString` | Profile.ets / ActivationStore.ets |

验证：空 URL 导入 toast（"请输入订阅 URL"）经新 PromptAction 通路正常弹出；8 页走查无崩溃。

### B. CodeLinter 告警清零（6 → 1）
- `await` 同步函数（`writeFile` 返回 void）→ 移除 4 处 await（DiagnosticCollector/GeoDataInstaller/ActivationStore×2）
- `no-state-var-access-in-loop`（Proxies testGroup）→ 循环外读一次快照（liveToken/baseGroups），批内比较用局部变量；渐进刷新改为结束后统一刷新（按钮已有"测速中"状态反馈）
- **保留 1 条**：`@performance/avoid-overusing-custom-component-check`（AppIcon）——尝试过转全局 @Builder，但 @Builder 不支持部分字段对象字面量参数与链式属性修饰符，跨文件复用场景下自定义组件是正确选择（已注释说明）

### C. 剩余 95 条编译告警（审查结论：可接受）
- 90 条 = "Function may throw exceptions"（JSON.parse/fileIo 调用点建议）——大部分在既有 try 块内或属于数据层惯用形态，逐处包裹属噪音，收益低
- 其余为 proxy_core 历史代码的同类提示
- 无 deprecated API 残留

## 结论
- CodeLinter：**0 error，1 可解释 warning**
- 编译告警：**169 → 95**，弃用 API 全部清除
- 构建通过，模拟器 8 页走查 + toast 通路验证通过
