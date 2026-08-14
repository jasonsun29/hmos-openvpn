/*
 * hmos-openvpn M3-3: 鸿蒙服务卡片（FormExtensionAbility）
 * v1 能力：
 *   - 展示 VPN 开关状态 + 当前模式（数据来自共享状态文件 vpn_state/selected_map）
 *   - 点击卡片打开应用
 * 数据流：UI（Home.toggleVpn/setMode）写共享文件 → 卡片 onAddForm/onUpdateForm 读文件
 *         并经 formProvider.updateForm 刷新
 */
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { SelectedMapStore } from 'proxy_core';

const TAG = 'VpnCardForm';

export default class VpnCardFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 初始数据（随后 onUpdateForm 会刷新为真实状态）
    return formBindingData.createFormBindingData({
      'vpnStatus': 'VPN 未连接',
      'modeText': ''
    });
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.refreshForm(formId);
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片点击事件（ArkTS 卡片用 postCardAction(router) 直接打开应用，
    // 此回调用于 message 类事件，暂不处理）
    console.log(TAG, 'onFormEvent: ' + formId + ' ' + message);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  onRemoveForm(formId: string): void {
    console.log(TAG, 'onRemoveForm: ' + formId);
  }

  // 读共享状态文件刷新卡片
  private refreshForm(formId: string): void {
    SelectedMapStore.loadVpnOn(this.context).then((on: boolean) => {
      SelectedMapStore.loadMode(this.context).then((mode: string) => {
        let modeText = '全局模式';
        if (mode.toUpperCase() === 'RULE') {
          modeText = '规则模式';
        } else if (mode.toUpperCase() === 'DIRECT') {
          modeText = '直连模式';
        }
        const data = formBindingData.createFormBindingData({
          'vpnStatus': on ? 'VPN 已连接' : 'VPN 未连接',
          'modeText': modeText
        });
        formProvider.updateForm(formId, data).then(() => {
          console.log(TAG, 'updateForm ok: ' + formId);
        }).catch((e: Error) => {
          console.error(TAG, 'updateForm failed: ' + e.message);
        });
      });
    });
  }
}
