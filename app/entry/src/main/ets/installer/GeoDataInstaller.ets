/*
 * hmos-openvpn P2-1: GeoDataInstaller
 * 内置 GeoIP / GeoSite / geoip.metadb / ASN.mmdb 到核心工作目录
 * （resfile → home），规则匹配必需
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { getHome, readFile, writeFile } from 'proxy_core';

// ArkTS 不允许对象字面量类型（arkts-no-obj-literals-as-types），声明为显式 interface
interface GeoFileStatus {
  name: string;
  ok: boolean;
}

export class GeoDataInstaller {
  private static readonly GEO_FILES: Array<string> = [
    'geoip.metadb',
    'GeoIP.dat',
    'GeoSite.dat',
    'ASN.mmdb'
  ];

  static async install(context: common.Context): Promise<boolean> {
    try {
      const home = await getHome(context);
      for (const f of GeoDataInstaller.GEO_FILES) {
        const src = context.resourceDir + '/' + f;
        const dst = home + '/' + f;
        const data: Uint8Array | null = await readFile(src);
        if (data) {
          writeFile(dst, data);
        }
      }
      console.log('GeoData', 'GeoX 数据就绪: ' + home);
      return true;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('GeoData', 'GeoX 安装失败: ' + msg);
      return false;
    }
  }

  static async verify(home: string): Promise<Array<GeoFileStatus>> {
    const result: Array<GeoFileStatus> = [];
    for (const f of GeoDataInstaller.GEO_FILES) {
      const p = home + '/' + f;
      let ok = false;
      try {
        ok = await fileIo.access(p);
      } catch (e) {
        ok = false;
      }
      const st: GeoFileStatus = { name: f, ok: ok };
      result.push(st);
    }
    return result;
  }
}