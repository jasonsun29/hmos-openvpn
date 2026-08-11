/*
 * hmos-openvpn M0b-3: VpnExtensionAbility（烟囱测试）
 * 参照 ClashBox ClashVpnAbility：同进程模型，onCreate 启动核心服务，onDestroy 停止
 */
import { VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { SocketStubService } from 'proxy_core';
import fs from '@ohos.file.fs';

export default class ClashVpnAbility extends VpnExtensionAbility {
  clashStubService: SocketStubService | undefined

  async onCreate(want: Want) {
    try {
      console.log('M0b3', 'VpnExtensionAbility onCreate');
      this.clashStubService = new SocketStubService(this.context);
      await this.clashStubService.startService();
      await this.clashStubService.startVpn();
      console.log('M0b3', 'VPN 核心启动成功');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M0b3', '启用VPN失败: ' + msg);
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
