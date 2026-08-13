/*
 * hmos-openvpn M1: VpnExtensionAbility（VPN 扩展，独立进程 :vpn）
 * 修复：onCreate 时加载激活的订阅配置到 Go 核心（否则 StartTUN 时 currentConfig=nil → 段错误崩溃）
 * 流程：startService（起 socket + Go 核心）→ loadActiveConfig（加载配置）→ startVpn（TUN 接管）
 */
import { VpnExtensionAbility, socket } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { SocketStubService, UpdateConfigParams, ClashConfig, ClashRpcType, ActivationStore, DnsEnhancedMode, TunStack, SelectedMapStore, ProxyMode } from 'proxy_core';
import { updateConfig } from 'libflclash.so';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

export default class ClashVpnAbility extends VpnExtensionAbility {
  clashStubService: SocketStubService | undefined

  async onCreate(want: Want) {
    try {
      console.log('VpnAbility', 'VpnExtensionAbility onCreate');
      this.clashStubService = new SocketStubService(this.context);
      await this.clashStubService.startService();
      // 加载激活的订阅配置（关键修复：否则 Go 核心 currentConfig=nil → StartTUN 段错误）
      await this.loadActiveConfig();
      // startVpn 返回 void（lint: await-thenable），不加 await
      this.clashStubService.startVpn();
      console.log('VpnAbility', 'VPN 核心启动成功');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('VpnAbility', '启用VPN失败: ' + msg);
    }
  }

  // 加载激活订阅配置到 Go 核心
  async loadActiveConfig(): Promise<void> {
    try {
      console.log('VpnAbility', 'loadActiveConfig start');
      // P1-2 ActivationStore 提供读路径：读跨进程文件 /active_profile.id
      let activeId: string = await ActivationStore.readActiveProfileIdFromFile(this.context.filesDir);
      // 方案2: 读 Preferences（同进程兜底）
      if (activeId === '') {
        try {
          const prefs = await preferences.getPreferences(this.context, 'app_state');
          activeId = prefs.getSync('active_profile_id', '') as string;
        } catch (e) {
          console.error('VpnAbility', '读Preferences失败: ' + String(e));
        }
      }
      console.log('VpnAbility', 'loadActiveConfig activeId=[' + activeId + ']');
      if (activeId === '') {
        console.warn('VpnAbility', '无激活订阅，跳过配置加载');
        return;
      }
      // P1-2 ActivationStore 提供 yaml 同步：确保 Go 侧 <id>.yaml 存在（内部会调 getHome 建目录）
      await ActivationStore.ensureGoConfigYaml(this.context, activeId);
      // VPN 进程内直接 NAPI 加载（libflclash 的 updateConfig 走 Go 核心 applyConfig → currentConfig 就绪）
      // 关键修复：
      // 1. override-dns: true + dns.enable: true —— 订阅若关闭 DNS，核心 URLTest 无法解析域名 → 测速全超时
      // 2. proxy-server-nameserver 用普通 DNS（223.5.5.5 直连）—— DoH(https://doh.pub) 解析节点域名时
      //    HTTPS 连接会被 TUN 捕获形成环路 → 节点解析挂起 → 连接超时（其他设备正常、手机卡死的根因）
      const cfg = new ClashConfig();
      if (cfg.dns) {
        cfg.dns.enable = true;
        cfg.dns['proxy-server-nameserver'] = ['223.5.5.5'];
        cfg.dns['default-nameserver'] = ['223.5.5.5'];
      }
      // P1-4 读取 pendingL3Patch（UI 进程的 Settings L3 变更后写入，VPN 重启后读一次应用并清空）
      try {
        const prefs = await preferences.getPreferences(this.context, 'app_settings');
        const pending: string = prefs.getSync('pending_l3_patch', '') as string;
        if (pending !== '') {
          // Settings 侧写入的就是字符串值（'fake-ip'/'redir-host'、'system'/'gvisor'/'mixed'）
          const patch: Record<string, string> = JSON.parse(pending) as Record<string, string>;
          // DNS 增强模式
          if (patch['dnsEnhancedMode'] !== undefined) {
            if (cfg.dns) {
              cfg.dns['enhanced-mode'] = patch['dnsEnhancedMode'] as DnsEnhancedMode;
            }
          }
          // TUN 栈
          if (patch['tunStack'] !== undefined) {
            if (!cfg.tun) {
              cfg.tun = new ClashConfig().tun;
            }
            if (cfg.tun) {
              cfg.tun.stack = patch['tunStack'] as TunStack;
              cfg.tun.enable = true;
            }
          }
          // 读完后清除（只应用一次）
          await prefs.put('pending_l3_patch', '');
          await prefs.flush();
          console.log('VpnAbility', '已应用 pending L3 patch: ' + pending);
        }
      } catch (e) {
        console.error('VpnAbility', '读 pendingL3Patch 失败: ' + String(e));
      }
      // P3 持久化恢复：上次选择的模式 + 各组的节点选择（跨进程共享文件）
      const persistedMode = await SelectedMapStore.loadMode(this.context);
      if (persistedMode !== '' && cfg.mode) {
        cfg.mode = persistedMode as ProxyMode;
        console.log('VpnAbility', '恢复持久化模式: ' + persistedMode);
      }
      const selectedMap = await SelectedMapStore.load(this.context, activeId);
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        'config': cfg,
        'params': {
          'is-patch': false,
          'is-compatible': false,
          'selected-map': selectedMap,
          'override-dns': true,
          'test-url': 'https://www.gstatic.com/generate_204'
        }
      };
      console.log('VpnAbility', 'loadActiveConfig calling updateConfig...');
      const result: string = await updateConfig(JSON.stringify(params));
      console.log('VpnAbility', 'loadActiveConfig result=[' + result + '] id=' + activeId);
      // 设置 TUN 选项（关键：tunIp 必须设置，否则 ParseConfig 不添加 IPv4 路由 0.0.0.0/0 → 流量不走 TUN）
      await this.setTunOptions();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('VpnAbility', 'loadActiveConfig failed: ' + msg);
    }
  }

  // 设置 TUN 选项（tunIp/ipv6/routeAddress），对齐 ClashBox loadVpnOptions
  async setTunOptions(): Promise<void> {
    try {
      const socketPath = this.context.filesDir + '/clash_go.sock';
      const options: TunRawOptions = {
        tunIp: '172.19.0.1/30',
        ipv6: true,
        routeAddress: ['0.0.0.0/0', '::/0'],
        accessControl: { mode: '', acceptList: [], rejectList: [] } as AccessControlOptions
      };
      const tcp: socket.LocalSocket = socket.constructLocalSocketInstance();
      const result: string = await new Promise<string>((resolve, reject) => {
        tcp.on('message', (value: socket.LocalSocketMessageInfo) => {
          const text = new util.TextDecoder().decodeToString(new Uint8Array(value.message));
          resolve(text);
          tcp.close();
        });
        tcp.on('error', () => {
          reject(new Error('socket error'));
        });
        tcp.connect({ address: { address: socketPath }, timeout: 1000 }).then(() => {
          tcp.send({ data: JSON.stringify({ method: ClashRpcType.setOptionState, params: [JSON.stringify(options)] }) });
        }).catch((e: Error) => {
          reject(e);
        });
      });
      console.log('VpnAbility', 'setTunOptions result=[' + result + ']');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('VpnAbility', 'setTunOptions failed: ' + msg);
    }
  }

  onDestroy() {
    console.log('VpnAbility', 'VpnExtensionAbility onDestroy');
    this.clashStubService?.stopVpn();
    const lockPath = this.context.filesDir + '/vpn_ipc.lock';
    try {
      fileIo.unlinkSync(lockPath);
    } catch (e) {
      // lock 文件不存在时忽略
    }
  }

  // ---- P2-2 静态文件工具已统一到 proxy_core/fileUtils，本地重复实现删除 ----
}

interface TunRawOptions {
  tunIp: string;
  ipv6: boolean;
  routeAddress: Array<string>;
  accessControl: AccessControlOptions;
}

interface AccessControlOptions {
  mode: string;
  acceptList: Array<string>;
  rejectList: Array<string>;
}
