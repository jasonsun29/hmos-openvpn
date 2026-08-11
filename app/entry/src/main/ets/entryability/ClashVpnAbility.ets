/*
 * hmos-openvpn M1: VpnExtensionAbility（VPN 扩展，独立进程 :vpn）
 * 修复：onCreate 时加载激活的订阅配置到 Go 核心（否则 StartTUN 时 currentConfig=nil → 段错误崩溃）
 * 流程：startService（起 socket + Go 核心）→ loadActiveConfig（加载配置）→ startVpn（TUN 接管）
 */
import { VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { SocketStubService, UpdateConfigParams, ClashConfig, getHome } from 'proxy_core';
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
      // VPN 进程内直接 NAPI 加载（libflclash 的 updateConfig 走 Go 核心 applyConfig → currentConfig 就绪）
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        config: new ClashConfig(),
        params: {
          'is-patch': false,
          'is-compatible': false,
          'selected-map': {},
          'override-dns': false,
          'test-url': 'http://www.gstatic.com/generate_204'
        }
      };
      console.log('M0b3', 'loadActiveConfig calling updateConfig...');
      const result: string = await updateConfig(JSON.stringify(params));
      console.log('M0b3', 'loadActiveConfig result=[' + result + '] id=' + activeId);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M0b3', 'loadActiveConfig failed: ' + msg);
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
}
