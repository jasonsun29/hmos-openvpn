/*
 * hmos-openvpn M0b-1: NAPI Bridge 最小验证页
 * 验证 libflclash.so 能加载、initClash 能初始化、核心数据函数能返回
 */
import { initClash, getProxies, getTraffic, getVpnOptions, validateConfig } from 'libflclash.so';
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';

@Entry
@Component
struct Index {
  @State message: string = '核心未加载';
  @State detail: string = '启动中...';
  @State loaded: boolean = false;

  aboutToAppear(): void {
    // M0b-1 自动验证：启动即依次验证核心各函数
    this.runAutoVerify();
  }

  async runAutoVerify(): Promise<void> {
    await this.doInitClash();
    await this.sleep(300);
    if (this.loaded) {
      this.doGetProxies();
      await this.sleep(300);
      this.doGetTraffic();
      await this.sleep(300);
      this.doGetVpnOptions();
      await this.sleep(300);
      await this.doValidateConfig();
      this.detail = this.detail + '\n--- 自动验证完成 ---';
    }
  }

  sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  build() {
    Column({ space: 12 }) {
      Text('hmos-openvpn M0b-1 核心验证')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40 })

      Text(this.message)
        .fontSize(16)
        .fontColor(this.loaded ? '#07C160' : '#FF3B30')

      Text(this.detail)
        .fontSize(12)
        .fontColor('#666')
        .padding(12)
        .width('90%')
        .textAlign(TextAlign.Start)

      Button('1. initClash（加载核心）')
        .width('80%')
        .onClick(() => this.doInitClash())

      Button('2. getProxies（查节点）')
        .width('80%')
        .enabled(this.loaded)
        .onClick(() => this.doGetProxies())

      Button('3. getTraffic（查流量）')
        .width('80%')
        .enabled(this.loaded)
        .onClick(() => this.doGetTraffic())

      Button('4. getVpnOptions（查VPN配置）')
        .width('80%')
        .enabled(this.loaded)
        .onClick(() => this.doGetVpnOptions())

      Button('5. validateConfig（校验配置）')
        .width('80%')
        .enabled(this.loaded)
        .onClick(() => this.doValidateConfig())

      Button('6. 开启 VPN（烟囱测试）')
        .width('80%')
        .backgroundColor('#07C160')
        .onClick(() => this.doStartVpn())

      Button('7. 关闭 VPN')
        .width('80%')
        .backgroundColor('#FF3B30')
        .onClick(() => this.doStopVpn())
    }
    .width('100%')
    .height('100%')
  }

  async doInitClash() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const home = context.filesDir + '/ClashBox';
      if (!await fs.access(home)) {
        fs.mkdirSync(home);
      }
      initClash(home, '1.0.0');
      this.loaded = true;
      this.message = '✅ 核心加载成功';
      this.detail = 'initClash OK\n工作目录: ' + home;
      console.log('M0b1', 'initClash success');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.message = '❌ 核心加载失败';
      this.detail = 'error: ' + msg;
      console.error('M0b1', 'initClash failed: ' + msg);
    }
  }

  doGetProxies() {
    try {
      const result: string = getProxies();
      this.detail = 'getProxies 返回:\n' + result.substring(0, 500);
      console.log('M0b1', 'getProxies len=' + result.length);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = 'getProxies error: ' + msg;
      console.error('M0b1', 'getProxies failed: ' + msg);
    }
  }

  doGetTraffic() {
    try {
      const result: string = getTraffic();
      this.detail = 'getTraffic 返回:\n' + result;
      console.log('M0b1', 'getTraffic: ' + result);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = 'getTraffic error: ' + msg;
    }
  }

  doGetVpnOptions() {
    try {
      const result: string = getVpnOptions();
      this.detail = 'getVpnOptions 返回:\n' + result;
      console.log('M0b1', 'getVpnOptions: ' + result);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = 'getVpnOptions error: ' + msg;
    }
  }

  async doValidateConfig() {
    try {
      const emptyProxies: Array<Object> = [];
      const emptyGroups: Array<Object> = [];
      const emptyRules: Array<Object> = [];
      const minimal = JSON.stringify({
        'mixed-port': 7890,
        'mode': 'rule',
        'log-level': 'info',
        'proxies': emptyProxies,
        'proxy-groups': emptyGroups,
        'rules': emptyRules
      });
      const result: string = await validateConfig(minimal);
      this.detail = 'validateConfig 返回:\n' + result;
      console.log('M0b1', 'validateConfig: ' + result);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = 'validateConfig error: ' + msg;
    }
  }

  async doStartVpn(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const vpnWant: Want = {
        deviceId: '',
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'ClashVpnAbility',
        parameters: { requestId: Date.now() }
      };
      this.detail = '请求系统授权...\n（请在弹窗中允许）';
      await vpnExtension.startVpnExtensionAbility(vpnWant);
      this.detail = 'startVpnExtensionAbility 调用成功\n系统弹窗应已出现';
      console.log('M0b3', 'startVpnExtensionAbility called');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = '启动 VPN 失败: ' + msg;
      console.error('M0b3', 'startVpnExtensionAbility failed: ' + msg);
    }
  }

  async doStopVpn(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const vpnWant: Want = {
        deviceId: '',
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'ClashVpnAbility'
      };
      await vpnExtension.stopVpnExtensionAbility(vpnWant);
      this.detail = 'VPN 已请求关闭';
      console.log('M0b3', 'stopVpnExtensionAbility called');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.detail = '关闭 VPN 失败: ' + msg;
      console.error('M0b3', 'stopVpnExtensionAbility failed: ' + msg);
    }
  }
}
