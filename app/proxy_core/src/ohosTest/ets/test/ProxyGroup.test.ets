/*
 * P2-14 ProxyGroup 解析单测
 *
 * 覆盖：
 * - ProxyType 枚举正确性（Selector / URLTest / Fallback / Direct / Unknown）
 * - ProxyGroup 接口字段完整性（type/name/proxies/now/hidden/icon）
 * - Proxy 接口字段（name/type/latency/id/g）
 * - JSON 序列化反序列化往返一致性
 *
 * 注：ProxyGroup 是 interface，没有工厂方法，直接构造对象后断言字段即可。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ProxyGroup, Proxy, ProxyType } from '../../../main/ets/models/Common';
import { JSON } from '@kit.ArkTS';

export default function proxyGroupTest() {
  describe('ProxyGroup', () => {
    it('constructs_with_required_fields', 0, () => {
      const proxies: Proxy[] = [{ name: 'HK-1', type: ProxyType.Shadowsocks }];
      const group: ProxyGroup = {
        type: ProxyType.Selector,
        name: 'Auto',
        proxies: proxies,
        now: 'HK-1'
      };
      expect(group.type).assertEqual(ProxyType.Selector);
      expect(group.name).assertEqual('Auto');
      expect(group.proxies.length).assertEqual(1);
      expect(group.now).assertEqual('HK-1');
    });

    it('optional_fields_default_undefined', 0, () => {
      const group: ProxyGroup = {
        type: ProxyType.Selector,
        name: 'Auto',
        proxies: [],
        now: ''
      };
      expect(group.hidden).assertUndefined();
      expect(group.icon).assertUndefined();
    });

    it('serializes_to_json_and_back', 0, () => {
      const original: ProxyGroup = {
        type: ProxyType.URLTest,
        name: 'AutoTest',
        proxies: [
          { name: 'JP-1', type: ProxyType.Vmess, latency: 120 },
          { name: 'US-1', type: ProxyType.Trojan, latency: 200 }
        ],
        now: 'JP-1',
        hidden: false,
        icon: '🌏'
      };
      const text: string = JSON.stringify(original);
      const parsed: ProxyGroup = JSON.parse(text) as ProxyGroup;
      expect(parsed.name).assertEqual(original.name);
      expect(parsed.type).assertEqual(original.type);
      expect(parsed.proxies.length).assertEqual(2);
      expect(parsed.proxies[0].latency).assertEqual(120);
      expect(parsed.icon).assertEqual('🌏');
    });

    it('proxy_type_enum_values', 0, () => {
      // 验证关键枚举值（不能混淆大小写）
      expect(ProxyType.Selector).assertEqual('Selector');
      expect(ProxyType.URLTest).assertEqual('URLTest');
      expect(ProxyType.Fallback).assertEqual('Fallback');
      expect(ProxyType.Direct).assertEqual('Direct');
      expect(ProxyType.Reject).assertEqual('Reject');
      expect(ProxyType.Unknown).assertEqual('Unknown');
    });

    it('proxy_with_latency_roundtrip', 0, () => {
      const proxy: Proxy = { name: 'SG-1', type: ProxyType.Hysteria2, latency: 95 };
      const text: string = JSON.stringify(proxy);
      const parsed: Proxy = JSON.parse(text) as Proxy;
      expect(parsed.latency).assertEqual(95);
    });
  });
}