/*
 * P2-14 测试套件聚合入口
 *
 * 测试套件组织：
 *   Ability.test.ets        - 框架冒烟测试
 *   SubscriptionInfo.test.ets - 订阅信息头解析
 *   TrafficValue.test.ets     - 流量单位换算
 *   ProxyGroup.test.ets       - 代理组结构 + 序列化
 *
 * 注：List.test.ets 在 build 时被 ohpm 自动收集为测试套件，
 *     这里显式调用各 suite 的 default export 以保证加载顺序。
 */
import abilityTest from './Ability.test';
import subscriptionInfoTest from './SubscriptionInfo.test';
import trafficValueTest from './TrafficValue.test';
import proxyGroupTest from './ProxyGroup.test';

export default function testsuite() {
  abilityTest();
  subscriptionInfoTest();
  trafficValueTest();
  proxyGroupTest();
}