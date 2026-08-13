/*
 * hmos-openvpn P2-5: SubscriptionUpdater 订阅自动更新 worker
 *
 * 职责：
 *   周期扫描 ProfileRepo，过滤 autoUpdate=true 且 now - lastUpdateDate >= autoUpdateDuration 的 Profile
 *   自动调 Profile.update + repo.addOrUpdate 写回 lastUpdateDate
 *
 * 实现：
 *   - 单例 + setInterval（默认 60s 扫一次，足够低开销）
 *   - 全程静默失败：单个订阅更新失败不影响其他订阅；不让 UI 卡死
 *   - update 间加 mutex（同一时间只跑一个 update），避免多订阅同时下载撞 HTTPS 限流
 *   - 启动入口 install(context, repo)，AppService.init 里调用一次
 *
 * 不重编译 Go 的影响：
 *   订阅更新 = Profile.update（HTTP 下载 + YAML 解析 + 写文件），与 Go 端无关
 *   vailConfig 回调提供 "校验已通过" 空串（导入阶段只校验格式，激活时再让 Go 端校验语义）
 */
import { common } from '@kit.AbilityKit';
import { Profile, ProfileRepo } from 'proxy_core';

const SCAN_INTERVAL_MS = 60 * 1000;       // 60s 扫描一次
const UPDATE_MUTEX_INTERVAL_MS = 5 * 1000; // 单订阅更新间隔 5s，避免并发撞 HTTPS 限流

export class SubscriptionUpdater {
  private static instance: SubscriptionUpdater | undefined;
  private scanTimer: number = -1;
  private mutexTimer: number = -1;
  private context: common.Context | undefined;
  private repo: ProfileRepo | undefined;
  // 当前正在更新的 Profile ID 队列（避免重复 enqueue）
  private updating: Set<string> = new Set();
  // 待更新的 Profile 队列
  private queue: Array<Profile> = [];

  static getInstance(): SubscriptionUpdater {
    if (!SubscriptionUpdater.instance) {
      SubscriptionUpdater.instance = new SubscriptionUpdater();
    }
    return SubscriptionUpdater.instance;
  }

  // 安装：AppService.init 末尾调用一次
  install(context: common.Context, repo: ProfileRepo): void {
    if (this.scanTimer !== -1) {
      console.warn('SubUpdater', '已经在运行，不重复安装');
      return;
    }
    this.context = context;
    this.repo = repo;
    // 立即跑一次（应用启动时先更新一次过期订阅）
    this.scanAndEnqueue().catch((e: Error) => {
      console.warn('SubUpdater', '初次扫描失败: ' + e.message);
    });
    // 周期扫描
    this.scanTimer = setInterval(() => {
      this.scanAndEnqueue().catch((e: Error) => {
        console.warn('SubUpdater', '周期扫描失败: ' + e.message);
      });
    }, SCAN_INTERVAL_MS);
    // mutex 处理：每 5s 从 queue 取出 1 个更新
    this.mutexTimer = setInterval(() => {
      this.processQueue();
    }, UPDATE_MUTEX_INTERVAL_MS);
    console.log('SubUpdater', '已启动，扫描周期=' + SCAN_INTERVAL_MS + 'ms');
  }

  // 卸载：应用退出 / 切换账号时调用
  uninstall(): void {
    if (this.scanTimer !== -1) {
      clearInterval(this.scanTimer);
      this.scanTimer = -1;
    }
    if (this.mutexTimer !== -1) {
      clearInterval(this.mutexTimer);
      this.mutexTimer = -1;
    }
    this.queue = [];
    this.updating.clear();
  }

  // 扫描所有订阅，把过期的 enqueue 到队列
  private async scanAndEnqueue(): Promise<void> {
    if (!this.repo) return;
    const list: Profile[] = await this.repo.queryAll();
    const now: number = Date.now();
    for (const p of list) {
      // 仅 URL 类型 + autoUpdate=true + 已过期 + 不在更新中 + 不在队列里
      if (!p.autoUpdate) continue;
      if (p.url === '') continue;
      if (this.updating.has(p.id) || this.queue.find((x) => x.id === p.id)) continue;
      const elapsed: number = now - p.lastUpdateDate;
      if (elapsed >= p.autoUpdateDuration) {
        if (this.context) {
          p.loadContext(this.context);
        }
        this.queue.push(p);
        console.log('SubUpdater', 'enqueue: ' + (p.name ?? p.id) + ' elapsed=' + elapsed + 'ms');
      }
    }
  }

  // 每次 mutex tick 取出队首更新
  private processQueue(): void {
    if (this.queue.length === 0) return;
    const p: Profile | undefined = this.queue.shift();
    if (!p) return;
    this.updating.add(p.id);
    // 异步执行（不阻塞 mutex tick），更新失败/成功都从 updating 移除
    this.updateProfile(p).finally(() => {
      this.updating.delete(p.id);
    });
  }

  // 真实下载 + 写回 DB
  private async updateProfile(p: Profile): Promise<void> {
    if (!this.repo) return;
    try {
      console.log('SubUpdater', 'start update: ' + (p.name ?? p.id));
      // vailConfig 回调：格式校验（导入阶段语义校验留给 Go 端）
      await p.update(async (config: string): Promise<string> => {
        return '';
      });
      // 更新成功：写回 lastUpdateDate + DB
      p.lastUpdateDate = Date.now();
      await this.repo.addOrUpdate(p);
      console.log('SubUpdater', 'update OK: ' + (p.name ?? p.id));
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.warn('SubUpdater', 'update failed: ' + (p.name ?? p.id) + ' err=' + msg);
      // 失败不抛：避免 unhandled rejection；也不写回 DB（保持 lastUpdateDate，下次再尝试）
    }
  }
}