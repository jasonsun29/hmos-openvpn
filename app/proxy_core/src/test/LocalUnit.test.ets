import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { ConfigReader, GlobalModeResolver } from '../main/ets/ConfigReader';

// 模拟真实机场订阅格式：proxy-groups 列表项为 "-" 单独成行、key 另起一行；无 GLOBAL 组
const SAMPLE_YAML = `mixed-port: 7890
mode: rule

proxies:
  - name: V1-528|香港|x1.0
    type: ss
    server: example.com
    port: 443
  - name: V1-550|台湾|x1.0
    type: ss
    server: example2.com
    port: 443

proxy-groups:
-
  name: 桔子云
  type: select
  proxies:
    - HK-自动选择
    - V1-528|香港|x1.0
-
  name: HK-自动选择
  type: url-test
  url: http://www.gstatic.com/generate_204
  interval: 300
  proxies:
    - V1-528|香港|x1.0
    - V1-550|台湾|x1.0

rules:
  - DOMAIN-SUFFIX,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,桔子云
`;

export default function localUnitTest() {
  describe('localUnitTest', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });
    it('assertContain', 0, () => {
      let a = 'abc';
      let b = 'b';
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    // P3 重构：离线解析
    it('config_reader_parses_groups_and_nodes', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      expect(view.groups.length).assertEqual(2);
      expect(view.groups[0].name).assertEqual('桔子云');
      expect(view.groups[0].proxies.length).assertEqual(2);
      expect(view.nodes.length).assertEqual(2);
      expect(view.isGroupName('HK-自动选择')).assertTrue();
      expect(view.isGroupName('V1-550|台湾|x1.0')).assertFalse();
      expect(view.findGroupContaining('V1-550|台湾|x1.0')).assertEqual('HK-自动选择');
      expect(view.findGroupContaining('不存在的节点')).assertEqual('');
    });

    // P3 重构：全局模式解析（默认全局 + 端点映射）
    it('resolver_defaults_to_global', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('', {}, view);
      expect(r.mode).assertEqual('GLOBAL');
      expect(Object.keys(r.selectedMap).length).assertEqual(0);
    });

    it('resolver_direct_endpoint', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('global', { 'GLOBAL': 'DIRECT' }, view);
      expect(r.mode).assertEqual('DIRECT');
    });

    it('resolver_group_endpoint', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('global', { 'GLOBAL': '桔子云' }, view);
      expect(r.mode).assertEqual('GLOBAL');
      expect(r.selectedMap['GLOBAL']).assertEqual('桔子云');
    });

    it('resolver_node_endpoint_maps_to_containing_group', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('global', { 'GLOBAL': 'V1-550|台湾|x1.0' }, view);
      expect(r.mode).assertEqual('GLOBAL');
      expect(r.selectedMap['GLOBAL']).assertEqual('HK-自动选择');
      expect(r.selectedMap['HK-自动选择']).assertEqual('V1-550|台湾|x1.0');
    });

    it('resolver_rule_mode_keeps_group_selections', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('rule', { '桔子云': 'HK-自动选择' }, view);
      expect(r.mode).assertEqual('RULE');
      expect(r.selectedMap['桔子云']).assertEqual('HK-自动选择');
    });

    it('resolver_stale_endpoint_falls_back_global_default', 0, () => {
      const view = ConfigReader.parse(SAMPLE_YAML);
      const r = GlobalModeResolver.resolve('global', { 'GLOBAL': '已下架节点' }, view);
      expect(r.mode).assertEqual('GLOBAL');
      expect(r.selectedMap['GLOBAL']).assertEqual(undefined);
    });
  });
}
