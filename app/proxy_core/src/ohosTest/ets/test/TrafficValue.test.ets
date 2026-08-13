/*
 * P2-14 TrafficValue 单测
 *
 * 覆盖：
 * - 字节 < 1024 → B 单位
 * - KB / MB / GB / TB 边界（包含 > 1024^4 的极端情况，约定走 TB）
 * - 0 / null / undefined 防御
 * - toString 格式（"123 B" / "1.0 KB" / 整数 GB 等）
 */
import { describe, it, expect } from '@ohos/hypium';
import { TrafficValue, TrafficUnit } from '../../../main/ets/models/Common';

export default function trafficValueTest() {
  describe('TrafficValue', () => {
    it('bytes_below_1KB_uses_B_unit', 0, () => {
      const tv: TrafficValue = new TrafficValue(500);
      expect(tv.unit).assertEqual(TrafficUnit.B);
      expect(tv.show).assertEqual(500);
      expect(tv.value).assertEqual(500);
    });

    it('1KB_uses_KB_unit', 0, () => {
      const tv: TrafficValue = new TrafficValue(1024);
      expect(tv.unit).assertEqual(TrafficUnit.KB);
      expect(tv.show).assertEqual(1);
    });

    it('1MB_uses_MB_unit', 0, () => {
      const tv: TrafficValue = new TrafficValue(1024 * 1024);
      expect(tv.unit).assertEqual(TrafficUnit.MB);
      expect(tv.show).assertEqual(1);
    });

    it('1GB_uses_GB_unit', 0, () => {
      const tv: TrafficValue = new TrafficValue(1024 * 1024 * 1024);
      expect(tv.unit).assertEqual(TrafficUnit.GB);
      expect(tv.show).assertEqual(1);
    });

    it('1TB_uses_TB_unit', 0, () => {
      const tv: TrafficValue = new TrafficValue(Math.pow(1024, 4));
      expect(tv.unit).assertEqual(TrafficUnit.TB);
      expect(tv.show).assertEqual(1);
    });

    it('handles_zero_value', 0, () => {
      const tv: TrafficValue = new TrafficValue(0);
      expect(tv.unit).assertEqual(TrafficUnit.B);
      expect(tv.show).assertEqual(0);
    });

    it('handles_undefined_as_zero', 0, () => {
      // null/undefined 防御：赋 0（构造参数已改为可选，直接传 undefined）
      const tv: TrafficValue = new TrafficValue(undefined);
      expect(tv.value).assertEqual(0);
    });

    it('toString_format', 0, () => {
      const tv: TrafficValue = new TrafficValue(1024);
      // toFixed(0) → "1 KB"
      expect(tv.toString()).assertEqual('1 KB');
    });

    it('TB_threshold_when_exceeding_1024^4', 0, () => {
      // 2 TB：仍走 TB 单位
      const tv: TrafficValue = new TrafficValue(Math.pow(1024, 4) * 2);
      expect(tv.unit).assertEqual(TrafficUnit.TB);
      expect(tv.show).assertEqual(2);
    });
  });
}