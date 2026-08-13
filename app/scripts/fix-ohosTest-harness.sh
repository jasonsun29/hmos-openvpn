#!/bin/bash
# fix-ohosTest-harness.sh
# 修复 hvigor 对 HAR 模块 ohosTest target 的模板生成缺陷：
# GenerateUnitTestTemplate 把 harness 生成到 <module>/.test/testability，
# 但 OhosTestCompileArkTS 的 srcEntry 解析到
# <module>/.test/default/intermediates/.test/testability/TestAbility.ets，
# 该目录不会自动生成 → 报 "srcEntry file ... does not exist"。
# 用法：hvigorw clean 后、hvigorw test onDeviceTest 前执行一次。
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "$0")/../proxy_core" && pwd)"
DST="$MODULE_DIR/.test/default/intermediates/.test/testability"
mkdir -p "$DST/pages"
# TestAbility：官方 withKit 模板，testsuite 相对路径指向 src/ohosTest/ets/test/List.test
cat > "$DST/TestAbility.ets" <<'EOF'
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Hypium } from '@ohos/hypium';
import testsuite from '../../../../../src/ohosTest/ets/test/List.test';

const ON_DESTROY_ERROR = -2;

export default class TestAbility extends UIAbility {
  abilityDelegator: abilityDelegatorRegistry.AbilityDelegator;

  constructor() {
    super();
    this.abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onCreate');
    let abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs;
    abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    hilog.info(0x0000, 'testTag', '%{public}s', 'start run testcase!!!');
    Hypium.hypiumTest(this.abilityDelegator, abilityDelegatorArguments, testsuite);
  }

  onDestroy() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onDestroy');
    this.abilityDelegator.finishTest('TestAbility onDestroy unexpectedly!', ON_DESTROY_ERROR, () => {
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onWindowStageCreate');
    windowStage.loadContent('testability/pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onWindowStageDestroy');
  }

  onForeground() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onForeground');
  }

  onBackground() {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onBackground');
  }
}
EOF
cat > "$DST/pages/Index.ets" <<'EOF'
@Entry
@Component
struct Index {
  @State message: string = 'Running tests...';

  build() {
    Row() {
      Column() {
        Text(this.message)
          .fontSize(50)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .height('100%')
  }
}
EOF
echo "ohosTest harness 已写入 $DST"
