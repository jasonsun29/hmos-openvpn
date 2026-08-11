#!/bin/bash
# hmos-openvpn 构建脚本：配好环境变量后跑 hvigorw assembleHap
set -e
export DEVECO_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$DEVECO_HOME/sdk
export HARMONYOS_SDK=$DEVECO_SDK_HOME/default/openharmony
export JAVA_HOME=$DEVECO_HOME/jbr/Contents/Home
export PATH=$PATH:$HARMONYOS_SDK/toolchains:$DEVECO_HOME/tools/ohpm/bin:$DEVECO_HOME/tools/hvigor/bin:$DEVECO_HOME/tools/node/bin

cd "$(dirname "$0")"
exec hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon "$@"
