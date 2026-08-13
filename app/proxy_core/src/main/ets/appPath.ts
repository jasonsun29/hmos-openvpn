import { Context } from '@kit.AbilityKit';
// P2-13 文件 API 统一：迁移到 @kit.CoreFileKit.fileIo
import { fileIo } from '@kit.CoreFileKit';

const profilesDirectoryName = "/profiles";


export async function getHome(context: Context | undefined): Promise<string>{
  let home = context?.filesDir + "/ClashBox"
  // P2-13 sync access 替代 async fs.access
  if (!fileIo.accessSync(home)) {
    fileIo.mkdirSync(home);
  }
  return home
}
export async function getProfilesPath(context: Context | undefined): Promise<string> {
  let dir = await getHome(context) + profilesDirectoryName
  if (!fileIo.accessSync(dir)) {
    fileIo.mkdirSync(dir);
  }
  return dir
}
export async function getProfilePath(context: Context | undefined, id: string) {
  return await getProfileDir(context, id) + `/config.yaml`
}
export async function getProfileDir(context: Context | undefined, id: string) {
  const directory = await getProfilesPath(context);
  // 兼容ClashMeta 核心的文件目录
  if (!fileIo.accessSync(directory + `/${id}`)) {
    fileIo.mkdirSync(directory + `/${id}`);
  }
  return directory + `/${id}`
}