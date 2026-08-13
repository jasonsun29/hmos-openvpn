// P2-9 Request.ts 考古清理：删除废弃的 IpCountryList / CallIpResolver / 旧 queryIpInfo / checkIp 注释代码（1-180 行）
// 仅保留 export 的 queryCurrentIpInfo / checkIp / queryIpInfo 实际代码
import { JSON } from "@kit.ArkTS";
import { http } from "@kit.NetworkKit";

export interface IpInfo {
  ip: string;
  country: string;
}

type IpInfoParser = (json: Record<string, any>) => IpInfo | null;

/** IP 信息来源配置 */
const ipInfoSources: Record<string, IpInfoParser> = {
  'https://ipapi.co/json': fromIpApiCoJson, // 此源支持 IPv6 的查询
  'https://api.vore.top/api/IPdata': fromIpDataJson, // 此源是之前默认的源
  'https://ipwho.is': fromIpWhoIsJson,
  'https://api.myip.com': fromMyIpJson,
  'https://ident.me/json': fromIdentMeJson,
  'http://ip-api.com/json': fromIpAPIJson,
  'https://api.ip.sb/geoip': fromIpSbJson,
  'https://ipinfo.io/json': fromIpInfoIoJson,
};

function fromIpDataJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ipinfo']['text'] as string;
    const ipdata = json['ipdata'] as object;

    let country = '';
    if (ipdata['info3']) {
      country = ipdata['info3'] as string;
    } else if (ipdata['info2']) {
      country = ipdata['info2'] as string;
    } else if (ipdata['info1']) {
      country = ipdata['info1'] as string;
    }

    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpWhoIsJson error:', e);
  }
  return null;
}

function fromIpInfoIoJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpInfoIoJson error:', e);
  }
  return null;
}

function fromIpApiCoJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country_name'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpApiCoJson error:', e);
  }
  return null;
}

function fromIpSbJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpSbJson error:', e);
  }
  return null;
}

function fromIpWhoIsJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpWhoIsJson error:', e);
  }
  return null;
}

function fromMyIpJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromMyIpJson error:', e);
  }
  return null;
}

function fromIpAPIJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['query'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIpAPIJson error:', e);
  }
  return null;
}

function fromIdentMeJson(json: Record<string, any>): IpInfo | null {
  try {
    const ip = json['ip'] as string;
    const country = json['country'] as string;
    if (ip && country) {
      return { ip, country };
    }
  } catch (e) {
    console.error('fromIdentMeJson error:', e);
  }
  return null;
}

/**
 * 请求 IP 信息
 * @param url API 地址
 * @param parser JSON 解析函数
 * @returns IpInfo 或 null
 */
async function requestIpInfo(url: string, parser: IpInfoParser): Promise<IpInfo | null> {
  const httpRequest = http.createHttp();
  try {
    console.log(`IPtest #requestIpInfo 请求 URL: ${url}`);
    const resp = await httpRequest.request(url, {
      connectTimeout: 5000,
      readTimeout: 3000
    });

    if (resp.responseCode !== 200) {
      console.warn(`IPtest #requestIpInfo 请求失败，状态码: ${resp.responseCode}`);
      return null;
    }

    const jsonStr = resp.result.toString();
    const json = JSON.parse(jsonStr) as Record<string, any>;
    console.log(`IPtest #requestIpInfo 响应数据: ${jsonStr}`);

    const result = parser(json);
    if (result) {
      console.log(`IPtest #requestIpInfo 解析成功: IP=${result.ip}, Country=${result.country}`);
    } else {
      console.warn(`IPtest #requestIpInfo 解析失败，JSON 格式不匹配`);
    }

    return result;
  } catch (e) {
    console.error(`IPtest #requestIpInfo 请求异常: ${url}`, e.message);
    return null;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 查询当前 IP 信息（包含 IP 地址和国家代码）
 * 优化：一次请求同时获取 IP 和国家信息，无需二次请求
 * @returns IpInfo 或 null
 */
export async function queryCurrentIpInfo(): Promise<IpInfo | null> {
  for (const [url, parser] of Object.entries(ipInfoSources)) {
    const result = await requestIpInfo(url, parser);
    if (result) {
      return result;
    }
  }
  console.warn('IPtest #queryCurrentIpInfo 所有来源请求失败');
  return null;
}

/**
 * 仅查询 IP 地址（向后兼容旧接口）
 * @deprecated 建议使用 queryCurrentIpInfo() 获取完整信息
 */
export async function checkIp(): Promise<string> {
  const result = await queryCurrentIpInfo();
  return result ? result.ip : 'Unknown';
}

/**
 * 仅查询国家代码（向后兼容旧接口）
 * @param ip IP 地址（新版本中此参数不再使用）
 * @deprecated 建议使用 queryCurrentIpInfo() 获取完整信息
 */
export async function queryIpInfo(ip: string): Promise<string> {
  const result = await queryCurrentIpInfo();
  return result ? result.country : '';
}