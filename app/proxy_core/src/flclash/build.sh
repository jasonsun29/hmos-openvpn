#!/bin/bash

# 设置架构和目标
arch="arm64"  # 可选值：amd64, arm64
target="aarch64"  # 可选值：x86_64, aarch64
outdir="arm64-v8a"  # 可选值：x86_64, arm64-v8a

# 设置 OHOS_NATIVE_HOME
OHOS_NATIVE_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"

# 基础编译标志
BASE_FLAGS="-Wno-error --sysroot=$OHOS_NATIVE_HOME/sysroot "

# 工具链路径
TOOLCHAIN="$OHOS_NATIVE_HOME/llvm"

# 设置环境变量
export CC="$TOOLCHAIN/bin/clang"
export CXX="$TOOLCHAIN/bin/clang++"
export LD="$TOOLCHAIN/bin/clang"
export CGO_AR="$TOOLCHAIN/bin/llvm-ar"
export GOASM="$TOOLCHAIN/bin/llvm-as"
export GOOS="linux"
export GOARCH="$arch"
export GOARM=""
export CGO_ENABLED="1"
export CGO_CXXFLAGS=""
export CGO_CFLAGS="-Wno-error --target=$target-linux-ohos $BASE_FLAGS"
export CGO_LDFLAGS=" --sysroot=$OHOS_NATIVE_HOME/sysroot --target=$target-linux-ohos"

# 源文件和输出文件
sourceFile="./"
outputFile="libflclash.so"

# P3-14（t43）构建模式：debug（默认，关优化+保留调试符号）/ release（优化+剥离符号+trimpath）
MODE="${1:-debug}"
if [ "$MODE" = "release" ]; then
  GCFLAGS=""
  LDFLAGS='-ldflags="-s -w" -trimpath'
else
  GCFLAGS='-gcflags="all=-N -l"'
  LDFLAGS=""
fi
echo "build mode: $MODE (gcflags=$GCFLAGS ldflags=$LDFLAGS)"

# 构建命令，生成共享库
GO_OHOS="$HOME/harmony-vpn-research/go-ohos/bin/go"
# 注: ClashBox 原 build.sh 有 -tlsmodegd（其定制工具链私有 flag），标准 go-ohos 1.25.12 不支持，已移除
# 注: release 的 -s -w 只影响 Go 符号表，c-shared 的 NAPI 导出表由 cgo 控制，理论安全（下次真正编译时验证）
"$GO_OHOS" build -buildmode c-shared -tags "ohos with_gvisor" $GCFLAGS $LDFLAGS -o $outputFile $sourceFile

# 检查编译结果
if [ -f "$outputFile" ]; then
    echo "success: $outputFile"
else
    echo "failed"
fi

# 复制生成的 .so 文件到指定目录
cp -f "$outputFile" "$PWD/../../libs/$outdir/$outputFile"
rm -f "$outputFile" 


# ubex > gvisor@v0.0-20240320004321-933faba989ec > pkg>tcpip>link >fdbased>~60 endpoint.go
#isSocketFD