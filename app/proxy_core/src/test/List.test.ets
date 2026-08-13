/*
 * 本地测试套件聚合入口
 * P3 验证补充：把 src/ohosTest 下的纯逻辑用例（SubscriptionInfo/TrafficValue/
 * ProxyGroup/Ability 冒烟）聚合进来，宿主机即可执行全部 21 个 case
 * （hvigor test 本地跑，无需真机；DevEco 6.1.1 对 HAR 模块的
 * onDeviceTest 管线有 sourceMaps.map 缺陷，见 scripts/fix-ohosTest-harness.sh 注释）。
 */
import localUnitTest from './LocalUnit.test';
import abilityTest from '../ohosTest/ets/test/Ability.test';
import subscriptionInfoTest from '../ohosTest/ets/test/SubscriptionInfo.test';
import trafficValueTest from '../ohosTest/ets/test/TrafficValue.test';
import proxyGroupTest from '../ohosTest/ets/test/ProxyGroup.test';

export default function testsuite() {
  localUnitTest();
  abilityTest();
  subscriptionInfoTest();
  trafficValueTest();
  proxyGroupTest();
}
