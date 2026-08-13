import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { patchGlobalGroupInYaml } from '../main/ets/YamlGlobalPatch';

// 模拟真实机场订阅格式：proxy-groups 列表项为 "-" 单独成行、key 另起一行；
// 无 GLOBAL 组（核心将自动创建，但成员只有组、连 DIRECT 都没有）
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

    // P3 全局模式修复：无 GLOBAL 组时插入 GLOBAL
    it('global_patch_inserts_GLOBAL_when_missing', 0, () => {
      const patched = patchGlobalGroupInYaml(SAMPLE_YAML);
      expect(patched).assertContain('- name: GLOBAL');
      // 特殊项 + 组名 + 节点名全量成员（单引号包裹）
      expect(patched).assertContain("- 'DIRECT'");
      expect(patched).assertContain("- 'REJECT'");
      expect(patched).assertContain("'桔子云'");
      expect(patched).assertContain("'HK-自动选择'");
      expect(patched).assertContain("'V1-528|香港|x1.0'");
      expect(patched).assertContain("'V1-550|台湾|x1.0'");
      // GLOBAL 插在 proxy-groups: 之后、原组之前
      expect(patched.indexOf('- name: GLOBAL')).assertLarger(patched.indexOf('proxy-groups:'));
      expect(patched.indexOf('- name: GLOBAL')).assertSmaller(patched.indexOf("name: 桔子云"));
      // 规则段原样保留
      expect(patched).assertContain('- DOMAIN-SUFFIX,cn,DIRECT');
      expect(patched).assertContain('- MATCH,桔子云');
    });

    it('global_patch_idempotent', 0, () => {
      const once = patchGlobalGroupInYaml(SAMPLE_YAML);
      const twice = patchGlobalGroupInYaml(once);
      expect(twice).assertEqual(once);
    });
  });
}
