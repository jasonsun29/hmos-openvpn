/*
 * P2-14 SubscriptionInfo 单测
 *
 * 覆盖：
 * - formHString: 标准 subscription-userinfo 头解析（upload / download / total / expire）
 * - formHString: 部分字段缺失（forward compat，缺字段=0）
 * - formHString: 空字符串 / undefined 返回 0 字段实例
 * - GetTotal / GetUsed / getExpire 静态访问器
 */
import { describe, it, expect } from '@ohos/hypium';
import { SubscriptionInfo, TrafficValue } from '../../../main/ets/models/Common';

export default function subscriptionInfoTest() {
  describe('SubscriptionInfo', () => {
    it('formHString_parses_all_fields', 0, () => {
      // 标准 subscription-userinfo 头
      const info: SubscriptionInfo = SubscriptionInfo.formHString(
        'upload=123456789; download=987654321; total=1073741824; expire=1735689600'
      );
      expect(info.upload).assertEqual(123456789);
      expect(info.download).assertEqual(987654321);
      expect(info.total).assertEqual(1073741824);
      expect(info.expire).assertEqual(1735689600);
    });

    it('formHString_handles_partial_fields', 0, () => {
      // 只有 upload + download（total/expire 缺 = 0）
      const info: SubscriptionInfo = SubscriptionInfo.formHString('upload=100; download=200');
      expect(info.upload).assertEqual(100);
      expect(info.download).assertEqual(200);
      expect(info.total).assertEqual(0);
      expect(info.expire).assertEqual(0);
    });

    it('formHString_returns_zeros_for_empty', 0, () => {
      // 空字符串：4 字段全 0
      const info: SubscriptionInfo = SubscriptionInfo.formHString('');
      expect(info.upload).assertEqual(0);
      expect(info.download).assertEqual(0);
      expect(info.total).assertEqual(0);
      expect(info.expire).assertEqual(0);
    });

    it('formHString_returns_zeros_for_undefined', 0, () => {
      // undefined：也返回 0 字段实例（防御）
      const info: SubscriptionInfo = SubscriptionInfo.formHString(undefined);
      expect(info.upload).assertEqual(0);
      expect(info.download).assertEqual(0);
    });

    it('GetTotal_returns_TrafficValue', 0, () => {
      const info: SubscriptionInfo = SubscriptionInfo.formHString('total=1073741824');
      const tv: TrafficValue | undefined = SubscriptionInfo.GetTotal(info);
      expect(tv).not().assertUndefined();
      expect(tv?.value).assertEqual(1073741824);
    });

    it('GetUsed_sums_upload_and_download', 0, () => {
      const info: SubscriptionInfo = SubscriptionInfo.formHString('upload=300; download=700');
      const tv: TrafficValue | undefined = SubscriptionInfo.GetUsed(info);
      expect(tv?.value).assertEqual(1000);
    });

    it('getExpire_returns_expire_field', 0, () => {
      const info: SubscriptionInfo = SubscriptionInfo.formHString('expire=1735689600');
      const expire: number | undefined = SubscriptionInfo.getExpire(info);
      expect(expire).assertEqual(1735689600);
    });
  });
}