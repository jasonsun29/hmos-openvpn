/*
 * hmos-openvpn T7.3a: 后台保活服务（对齐 ClashBox BackgroundDownService）
 * 方案：backgroundTaskManager 长时任务 + downloadTemplate 常驻通知（10s 更新流量）
 * 目标：灭屏 30min 存活率 ≥95%，断流自动恢复 ≤10s（T7.3b 观测）
 */
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppService } from './AppService';

export class BackgroundKeepAliveService {
  private notificationId?: number = undefined;
  private noticeTimer?: number;
  private static instance: BackgroundKeepAliveService | undefined;

  static getInstance(): BackgroundKeepAliveService {
    if (!BackgroundKeepAliveService.instance) {
      BackgroundKeepAliveService.instance = new BackgroundKeepAliveService();
    }
    return BackgroundKeepAliveService.instance;
  }

  // 启动长时任务 + 常驻通知
  async start(context: common.Context): Promise<void> {
    if (this.notificationId !== undefined) {
      console.log('T7', '保活任务已在运行');
      return;
    }
    const id = await this.startContinuousTask(context);
    if (id < 0) {
      console.error('T7', '无法启动后台长时任务');
      return;
    }
    this.notificationId = id;
    // 10s 更新通知流量
    this.noticeTimer = setInterval(() => {
      this.updateTraffic(context);
    }, 10000);
    console.log('T7', '后台保活已启动');
  }

  async stop(context: common.Context): Promise<void> {
    if (this.noticeTimer !== undefined) {
      clearInterval(this.noticeTimer);
      this.noticeTimer = undefined;
    }
    this.notificationId = undefined;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      console.log('T7', '后台保活已停止');
    } catch (e) {
      console.error('T7', '停止后台任务失败: ' + String(e));
    }
  }

  // 长时任务（数据下载类型）
  private async startContinuousTask(context: common.Context): Promise<number> {
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          { bundleName: 'com.hmos.openvpn', abilityName: 'EntryAbility' }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      const result = await backgroundTaskManager.startBackgroundRunning(context,
        ['dataTransfer'], wantAgentObj);
      const id: number = result.notificationId;
      return id;
    } catch (e) {
      const err = e as BusinessError;
      console.error('T7', 'startContinuousTask failed: ' + err.code + ' ' + err.message);
      return -1;
    }
  }

  // 更新常驻通知（downloadTemplate 下载进度条）
  private async updateTraffic(context: common.Context): Promise<void> {
    try {
      const svc = AppService.getInstance().getProxyService();
      if (!svc) return;
      const t = await svc.queryTrafficNow(true);
      const down: number = t.downRaw ?? 0;
      const up: number = t.upRaw ?? 0;
      const message = AppService.formatBytes(up) + '/s ↑  ' + AppService.formatBytes(down) + '/s ↓';
      if (this.notificationId !== undefined) {
        this.updateProcess(this.notificationId, message);
      }
    } catch (e) {
      console.error('T7', 'updateTraffic: ' + String(e));
    }
  }

  private updateProcess(id: number, message: string): void {
    notificationManager.isSupportTemplate('downloadTemplate').then((supported: boolean) => {
      if (!supported) return;
      const template: notificationManager.NotificationTemplate = {
        name: 'downloadTemplate',
        data: {
          title: message,
          fileName: 'VPN 隧道运行中',
          progressValue: 99.9
        }
      };
      const request: notificationManager.NotificationRequest = {
        id: id,
        notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
        template: template,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
          systemLiveView: {
            typeCode: 8,
            title: message,
            text: message
          }
        },
        deliveryTime: Date.now(),
        isLocalOnly: true
      } as notificationManager.NotificationRequest;
      notificationManager.publish(request).catch((e: BusinessError) => {
        console.error('T7', 'publish notification: ' + e.code + ' ' + e.message);
      });
    });
  }
}
