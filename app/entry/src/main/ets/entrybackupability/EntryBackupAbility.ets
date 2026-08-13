/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;
// P3-13 关键备份数据清单（backup_config.json includes 与此保持一致）
const DB_FILES: Array<string> = ['fsclash.db', 'fsclash.db-wal', 'fsclash.db-shm'];
const STATE_FILE = 'active_profile.id';
const PROFILES_DIR = 'profiles';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    try {
      const filesDir: string = this.context.filesDir;
      const backupDir: string = this.context.backupDir;
      // 1) RDB：fsclash.db（+ wal/shm 若存在）
      for (const name of DB_FILES) {
        this.copyIfExists(filesDir + '/' + name, backupDir + '/' + name);
      }
      // 2) 激活订阅状态文件（跨进程文件）
      this.copyIfExists(filesDir + '/' + STATE_FILE, backupDir + '/' + STATE_FILE);
      // 3) profiles/ 目录（yaml 配置）
      if (fileIo.accessSync(filesDir + '/' + PROFILES_DIR)) {
        await fileIo.copyDir(filesDir + '/' + PROFILES_DIR, backupDir + '/' + PROFILES_DIR);
      }
      hilog.info(DOMAIN, 'testTag', 'onBackup ok');
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onBackup failed: %{public}s', JSON.stringify(e));
    }
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    try {
      const filesDir: string = this.context.filesDir;
      const backupDir: string = this.context.backupDir;
      // 恢复顺序：目录 → 文件（RDB 下次 init 读到新数据，无需重启 AppService）
      if (fileIo.accessSync(backupDir + '/' + PROFILES_DIR)) {
        await fileIo.copyDir(backupDir + '/' + PROFILES_DIR, filesDir + '/' + PROFILES_DIR);
      }
      for (const name of DB_FILES) {
        this.copyIfExists(backupDir + '/' + name, filesDir + '/' + name);
      }
      this.copyIfExists(backupDir + '/' + STATE_FILE, filesDir + '/' + STATE_FILE);
      hilog.info(DOMAIN, 'testTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onRestore failed: %{public}s', JSON.stringify(e));
    }
  }

  private copyIfExists(src: string, dest: string): void {
    if (fileIo.accessSync(src)) {
      fileIo.copyFileSync(src, dest);
    }
  }
}
