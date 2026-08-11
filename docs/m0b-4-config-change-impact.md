# hmos-openvpn 配置变更影响分级表（M0b-4 交付物·初步版）

> 日期：2026-08-11　依据：mihomo v1.17.1 源码字段（config.go 1844 行）+ ClashBox 热加载实测
> 状态：🟡 初步版（字段清单已核对源码），待真机逐字段实测后定稿
> 方法：逐字段二值实验（改 + reload + 观察断流/重建），产出 L1–L4 映射

## 分级定义

| 级别 | 含义 | 过渡策略 |
|---|---|---|
| L1 | 热加载无感 | UI 无感知，直接生效 |
| L2 | 热加载瞬断 | UI toast"应用中" |
| L3 | 需重建 TUN（fd 重传） | UI 显式提示"TUN 重建中，预计断流 N 秒" |
| L4 | 仅进程重启可达 | 走核心级重置流程（Go runtime 不可重启约束） |

## 字段分级（源码对照）

### L1 热加载无感
| 字段 | 类型 | 源码位置 |
|---|---|---|
| `mode`（rule/global/direct/script） | TunnelMode | config.go:47 |
| `unified-delay` | bool | config.go:48 |
| `log-level` | LogLevel | config.go:49 |
| `tcp-concurrent` | bool | config.go:59 |
| `geodata-mode` / `geodata-loader` | bool/string | config.go:56-57 |
| `sniffing` | bool | config.go:61 |
| `global-client-fingerprint` | string | config.go:62 |
| `global-ua` | string | config.go:63 |
| `etag-support` | bool | config.go:64 |
| `keep-alive-*` | int/bool | config.go:65-67 |
| `proxies` / `proxy-groups` / `rules` | 列表 | 核心规则段 |
| `rule-providers` / `proxy-providers` | 列表 | 提供者段 |

### L2 热加载瞬断
| 字段 | 类型 | 源码位置 |
|---|---|---|
| `port` / `socks-port` / `mixed-port` / `redir-port` / `tproxy-port` | int | config.go:72-76 |
| `allow-lan` | bool | config.go:85 |
| `bind-address` | string | config.go:86 |
| `authentication` / `skip-auth-prefixes` | 列表 | config.go:81-82 |
| `hosts` | map | DNS hosts 段 |

### L3 需重建 TUN（fd 重传）
| 字段 | 类型 | 源码位置 |
|---|---|---|
| `tun.enable` | bool | tun.go:15 |
| `tun.stack`（system/gvisor/mixed） | TUNStack | tun.go:15 |
| `tun.dns-hijack` | []string | tun.go:16 |
| `tun.auto-route` | bool | tun.go:17 |
| `tun.auto-detect-interface` | bool | tun.go:18 |
| `tun.mtu` | uint32 | tun.go:20 |
| `tun.route-address` | []netip.Prefix | tun.go:23 |
| `tun.strict-route` | bool | tun.go:21 |
| `dns.enable` / `dns.listen` | bool/string | DNS 段 |
| `dns.enhanced-mode`（fake-ip/redir-host） | DnsEnhancedMode | DNS 段 |
| `dns.fake-ip-range` | string | DNS 段 |
| `dns.nameserver` | 列表 | DNS 段 |
| `ipv6` | bool | config.go:50（影响 TUN 栈行为） |

### L4 仅进程重启可达
| 字段 | 类型 | 源码位置 |
|---|---|---|
| `interface-name` | string | config.go:51 |
| `routing-mark` | int | config.go:52 |
| `tun.device` | string | tun.go:14（指定网卡名） |
| `external-controller`（如启用） | string | 控制器段 |

## 与设计文档的衔接

- L3 触发时走 §3.4 TUN 重建子流：UI 收到 `TunnelStateChanged(Reconstructing)` → 停旧 fd → rebuildTun → startTun(newFd) → `TunnelStateChanged(Running)`
- L4 触发时走 §3.5.2 核心级重置流程（通知 UI → 断 TUN → 进程退出 → 重启应用）
- settings 页各设置项已按此标注（§4 settings 行）

## 待真机实测项（M0b-4 实测定稿）

1. `mixed-port` 修改是否真瞬断（实测断流时长）
2. `tun.stack` system↔gvisor 切换是否触发 TUN 重建（观察 fd 是否变化）
3. `dns.enhanced-mode` 切换时连接保持情况
4. `ipv6` 开关对现有连接的影响
5. 各字段 reload 报错时的回滚行为
