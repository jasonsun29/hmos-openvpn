/*
 * hmos-openvpn M1: VpnExtensionAbility（VPN 扩展，独立进程 :vpn）
 * 修复：onCreate 时加载激活的订阅配置到 Go 核心（否则 StartTUN 时 currentConfig=nil → 段错误崩溃）
 * 流程：startService（起 socket + Go 核心）→ loadActiveConfig（加载配置）→ startVpn（TUN 接管）
 */
import { VpnExtensionAbility, socket } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { SocketStubService, UpdateConfigParams, ClashConfig, getHome, ClashRpcType } from 'proxy_core';
import { updateConfig } from 'libflclash.so';
import fs from '@ohos.file.fs';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

export default class ClashVpnAbility extends VpnExtensionAbility {
  clashStubService: SocketStubService | undefined

  async onCreate(want: Want) {
    try {
      console.log('M0b3', 'VpnExtensionAbility onCreate');
      this.clashStubService = new SocketStubService(this.context);
      await this.clashStubService.startService();
      // 加载激活的订阅配置（关键修复：否则 Go 核心 currentConfig=nil → StartTUN 段错误）
      await this.loadActiveConfig();
      await this.clashStubService.startVpn();
      console.log('M0b3', 'VPN 核心启动成功');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M0b3', '启用VPN失败: ' + msg);
    }
  }

  // 加载激活订阅配置到 Go 核心
  async loadActiveConfig(): Promise<void> {
    try {
      console.log('M0b3', 'loadActiveConfig start');
      // 方案1: 读共享状态文件（跨进程可靠）
      let activeId: string = '';
      try {
        const statePath = this.context.filesDir + '/active_profile.id';
        const exists = await fs.access(statePath);
        if (exists) {
          const file = await fs.open(statePath, fs.OpenMode.READ_ONLY);
          const buf = new ArrayBuffer(64);
          await fs.read(file.fd, buf);
          fs.closeSync(file);
          activeId = new util.TextDecoder().decodeWithStream(new Uint8Array(buf)).replace(/\0/g, '').trim();
        }
      } catch (e) {
        console.error('M0b3', '读状态文件失败: ' + String(e));
      }
      // 方案2: 读 Preferences（同进程兜底）
      if (activeId === '') {
        try {
          const prefs = await preferences.getPreferences(this.context, 'app_state');
          activeId = prefs.getSync('active_profile_id', '') as string;
        } catch (e) {
          console.error('M0b3', '读Preferences失败: ' + String(e));
        }
      }
      console.log('M0b3', 'loadActiveConfig activeId=[' + activeId + ']');
      if (activeId === '') {
        console.warn('M0b3', '无激活订阅，跳过配置加载');
        return;
      }
      const home = await getHome(this.context);
      // 确保 Go 侧配置格式存在：profiles/<id>.yaml（Go 核心读取路径）
      const goCfgPath = home + '/profiles/' + activeId + '.yaml';
      const arkCfgPath = home + '/profiles/' + activeId + '/config.yaml';
      if (!(await ClashVpnAbility.fileExists(goCfgPath)) && (await ClashVpnAbility.fileExists(arkCfgPath))) {
        const data = await ClashVpnAbility.readFile(arkCfgPath);
        if (data) {
          await ClashVpnAbility.writeFile(goCfgPath, data);
          console.log('M0b3', '已从ArkTS格式复制Go配置: ' + activeId + '.yaml');
        }
      }
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
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        'config': cfg,
        'params': {
          'is-patch': false,
          'is-compatible': false,
          'selected-map': {},
          'override-dns': true,
          'test-url': 'https://www.gstatic.com/generate_204'
        }
      };
      console.log('M0b3', 'loadActiveConfig calling updateConfig...');
      const result: string = await updateConfig(JSON.stringify(params));
      console.log('M0b3', 'loadActiveConfig result=[' + result + '] id=' + activeId);
      // 设置 TUN 选项（关键：tunIp 必须设置，否则 ParseConfig 不添加 IPv4 路由 0.0.0.0/0 → 流量不走 TUN）
      await this.setTunOptions();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M0b3', 'loadActiveConfig failed: ' + msg);
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
      console.log('M0b3', 'setTunOptions result=[' + result + ']');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M0b3', 'setTunOptions failed: ' + msg);
    }
  }

  onDestroy() {
    console.log('M0b3', 'VpnExtensionAbility onDestroy');
    this.clashStubService?.stopVpn();
    const lockPath = this.context.filesDir + '/vpn_ipc.lock';
    try {
      fs.unlinkSync(lockPath);
    } catch (e) {
      // lock 文件不存在时忽略
    }
  }

  // ---- 静态文件工具（跨进程共享 filesDir）----
  static async fileExists(path: string): Promise<boolean> {
    try {
      return await fs.access(path);
    } catch (e) {
      return false;
    }
  }

  static async readFile(filePath: string): Promise<Uint8Array | null> {
    try {
      const file = await fs.open(filePath);
      const stats = await fs.stat(filePath);
      const buf = new ArrayBuffer(stats.size);
      await fs.read(file.fd, buf);
      fs.closeSync(file);
      return new Uint8Array(buf);
    } catch (e) {
      return null;
    }
  }

  static async writeFile(filePath: string, data: Uint8Array): Promise<void> {
    const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    await fs.write(file.fd, data.buffer);
    fs.closeSync(file);
  }
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
