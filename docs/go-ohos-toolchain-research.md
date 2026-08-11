---

# OpenHarmony Go 工具链 (go-ohos) 调研报告

## 一、go-ohos 工具链官方仓库

### 1.1 OpenHarmony SIG 官方仓库（上游）

| 项目 | 详情 |
|------|------|
| **仓库地址** | https://gitee.com/openharmony-sig/ohos_golang_go |
| **状态** | **关闭/归档**（页面标注"关闭"） |
| **基础 Go 版本** | Go 1.22 release branch |
| **主要 tag** | `2024-12-17_11_42_27/github.com/golang/go/release-branch.go1.22`（唯一公开可见的 tag） |
| **内部 tag** | `go1.24.5.ohosv1r1` — 在 `yourblacksky/ohos_golang_go` 的 OPENHARMONY_ECS.md 中被引用为移植来源，但 Gitee 上该 tag 的 tree 页面 404（未确认：可能需要登录或已被清理） |

### 1.2 活跃维护 Fork（推荐使用）

| 项目 | 详情 |
|------|------|
| **仓库地址** | https://github.com/yourblacksky/ohos_golang_go |
| **分支** | `release-branch.go1.25` |
| **Go 版本** | **Go 1.25.12**（VERSION 文件确认） |
| **描述** | "Go 1.25 OpenHarmony toolchain fork for ECS" |
| **来源** | 从 OpenHarmony SIG 的 `go1.24.5.ohosv1r1` tag 移植 OpenHarmony target 支持，新增 ARM64 general-dynamic TLS 和 OpenHarmony pthread TSD 集成 |

**结论**：官方 Gitee 仓库已归档且基于较老的 Go 1.22。实际生产使用应选用 `yourblacksky/ohos_golang_go`，它基于 Go 1.25.12 且专门为 macOS 交叉编译场景做了适配。

---

## 二、macOS arm64 上安装 go-ohos 工具链

### 2.1 无预编译 release 包

**必须从源码编译**。`yourblacksky/ohos_golang_go` 没有发布任何 release。OpenHarmony SIG 原仓库也没有提供 macOS arm64 的预编译二进制包。

### 2.2 从源码编译完整步骤

**前置条件**：macOS 上需要已安装一个标准 Go（作为 bootstrap），建议 Go ≥ 1.20。

```bash
# 1. 克隆仓库
git clone https://github.com/yourblacksky/ohos_golang_go.git
cd ohos_golang_go
git checkout release-branch.go1.25

# 2. 编译 Go 工具链（仅编译主机工具链，不跑测试）
cd src
GOTOOLCHAIN=local ./make.bash

# 3. 验证编译结果
cd ..
./bin/go version
# 期望输出: go version go1.25.12 darwin/arm64
```

**关键说明**：
- `./make.bash`（不是 `./all.bash`）——只编译工具链，不跑测试套件。`./all.bash` 会跑全部测试，耗时很长且可能因 OHOS 特定测试失败。
- `GOTOOLCHAIN=local` 强制使用本地源码编译，不从网络下载 toolchain。
- 不需要额外环境变量，系统已有的 Go 会自动被检测为 `GOROOT_BOOTSTRAP`。
- 编译产物在 `ohos_golang_go/bin/go`，即 `go-ohos` 工具链入口。

---

## 三、编译参数详解

### 3.1 `-tags "ohos with_gvisor"` 中各 tag 的作用

#### `ohos` tag

在 ClashBox 的 `proxy_core/src/flclash/` 中，`ohos` 是条件编译标记：

- **main.go**：`//go:build !cgo` — 非 cgo 模式，仅用于 IPC 模式
- **main_cgo.go**：`//go:build cgo && ohos` — **cgo + ohos 模式**，是鸿蒙 .so 编译的入口。此文件通过 `github.com/likuai2010/ohos-napi` 注册 NAPI 函数，供 ArkTS 层调用
- **lib_linux.go**：`//go:build ohos && cgo` — TUN 设备模拟、Socket 保护、进程映射等 OHOS 特定平台实现

**作用**：`ohos` tag 选中了 OHOS 专用的 NAPI 导出入口和平台实现，而非 Linux/Android 的 TUN fd 传递方式。

#### `with_gvisor` tag

在 mihomo 内核中，`with_gvisor` 启用 gvisor 用户态 TCP/IP 网络栈。因为鸿蒙没有 Linux TUN 设备，mihomo 的 `sing-tun` 在 `features.OHOS` 为 true 时走 gvisor 网络栈。`with_gvisor` tag 在 mihomo 内部编译时引入 gvisor 依赖。

### 3.2 gvisor-ohos 是什么

- **仓库地址**：https://github.com/likuai2010/gvisor-ohos
- **来源**：fork 自 `MetaCubeX/gvisor`（mihomo 使用的 gvisor 分支）
- **分支**：`meta-20250325-9e676ea1de20`
- **在 ClashBox 中的引入方式**：Git submodule，路径 `proxy_core/src/flclash/gvisor-ohos`
- **go.mod 中的 replace**：`github.com/metacubex/gvisor => ./gvisor-ohos`
- **ClashBox .gitmodules 记录**：
  ```
  [submodule "proxy_core/src/flclash/gvisor-ohos"]
      path = proxy_core/src/flclash/gvisor-ohos
      url = https://github.com/likuai2010/gvisor-ohos.git
  ```

**获取方式**：clone ClashBox 后执行 `git submodule update --init --recursive` 即可拉取。ClashBox 仓库里**不直接包含** gvisor-ohos 源码，而是通过 submodule 引用。

---

## 四、ohos-napi 的作用和获取方式

### 4.1 仓库信息

| 项目 | 详情 |
|------|------|
| **仓库地址** | https://github.com/likuai2010/ohos-napi |
| **版本** | v1.0.3（ClashBox go.mod 中引用） |
| **来源** | fork 自 `akshayganeshen/napi-go` |
| **语言** | Go + C |

### 4.2 作用

ohos-napi 是 **Go 语言的 NAPI (Node-API) 绑定库**，让 Go 编译的 .so 能够导出函数供鸿蒙 ArkTS/JS 运行时调用。核心能力：

- `entry.Export(name, callback)` — 注册导出函数
- `js.Env`, `js.Value` — 封装 NAPI 环境与值操作
- `env.CreateThreadsafeFunction()` — 创建线程安全回调（用于 Go goroutine 向 ArkTS 主线程发消息）
- `env.NewPromise()` — 创建 Promise（支持异步操作）

在 `main_cgo.go` 中，`init()` 函数通过 `entry.Export()` 注册了约 30 个函数（`initClash`, `startTun`, `updateConfig`, `changeProxy` 等），这些函数编译进 `libflclash.so` 后，ArkTS 侧通过 NAPI 直接调用。

### 4.3 获取方式

**go mod 直接拉取即可**，无需额外操作：

```bash
go get github.com/likuai2010/ohos-napi@v1.0.3
```

该库会被 go mod 自动下载到模块缓存中。编译时 CGO 会链接其内部的 `gonapi.c`/`gonapi.h`。

---

## 五、macOS arm64 完整编译命令清单

### 5.1 前置准备

```bash
# 0. 确保系统已安装标准 Go（作为 bootstrap）
brew install go
go version  # 确认 Go 已安装

# 安装 DevEco Studio（获取 OHOS Native SDK / LLVM 工具链）
# 下载地址: https://developer.huawei.com/consumer/cn/deveco-studio/
# 安装后，OHOS Native 默认路径:
#   /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
```

### 5.2 编译 go-ohos 工具链

```bash
# 1. 克隆 go-ohos 工具链
git clone https://github.com/yourblacksky/ohos_golang_go.git
cd ohos_golang_go
git checkout release-branch.go1.25

# 2. 编译
cd src
GOTOOLCHAIN=local ./make.bash

# 3. 验证
cd ..
./bin/go version
# 期望: go version go1.25.12 darwin/arm64

# 4. 记下 GOROOT 路径
export GOROOT_OHOS="$PWD"
```

### 5.3 验证交叉编译 helloworld.so

```bash
# 5. 创建测试项目
mkdir -p ~/ohos-test && cd ~/ohos-test

cat > main.go << 'GOEOF'
package main

import "C"
import "fmt"

//export HelloWorld
func HelloWorld() *C.char {
    return C.CString("Hello from Go on OpenHarmony!")
}

func main() {
    fmt.Println("This is a shared library, not an executable")
}
GOEOF

# 6. 设置 OHOS NDK 路径
OHOS_NATIVE_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
TOOLCHAIN="$OHOS_NATIVE_HOME/llvm"

# 7. 编译（使用 go-ohos 工具链 + OHOS clang）
GOROOT="$GOROOT_OHOS" \
GOTOOLCHAIN=local \
CGO_ENABLED=1 \
GOOS=openharmony \
GOARCH=arm64 \
CC="$TOOLCHAIN/bin/clang" \
CGO_CFLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_NATIVE_HOME/sysroot" \
CGO_LDFLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_NATIVE_HOME/sysroot" \
"$GOROOT_OHOS/bin/go" build -buildmode=c-shared -o libhelloworld.so .

# 8. 验证产物
file libhelloworld.so
# 期望: libhelloworld.so: ELF 64-bit LSB shared object, ARM aarch64, ...
```

### 5.4 编译完整 mihomo (ClashBox 内核) 的命令

```bash
# 9. 克隆 ClashBox 及子模块
git clone --recurse-submodules https://github.com/xiaobaigroup/ClashBox.git
cd ClashBox
git checkout master

# 10. 进入 flclash 目录
cd proxy_core/src/flclash

# 11. 设置环境变量（参考 build.sh）
OHOS_NATIVE_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
TOOLCHAIN="$OHOS_NATIVE_HOME/llvm"

export CC="$TOOLCHAIN/bin/clang"
export CXX="$TOOLCHAIN/bin/clang++"
export CGO_AR="$TOOLCHAIN/bin/llvm-ar"
export GOASM="$TOOLCHAIN/bin/llvm-as"
export CGO_ENABLED=1
export GOOS=openharmony
export GOARCH=arm64
export CGO_CFLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_NATIVE_HOME/sysroot"
export CGO_LDFLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_NATIVE_HOME/sysroot"

# 12. 编译（使用 go-ohos 工具链）
GOROOT="$GOROOT_OHOS" \
GOTOOLCHAIN=local \
"$GOROOT_OHOS/bin/go" build \
  -buildmode c-shared \
  -tags "ohos with_gvisor" \
  -o libflclash.so \
  .

# 13. 验证
file libflclash.so
```

---

## 六、来源链接汇总

| 项目 | 链接 |
|------|------|
| OpenHarmony SIG go-ohos (官方归档) | https://gitee.com/openharmony-sig/ohos_golang_go |
| yourblacksky go-ohos (活跃维护) | https://github.com/yourblacksky/ohos_golang_go |
| yourblacksky OPENHARMONY_ECS.md | https://github.com/yourblacksky/ohos_golang_go/blob/release-branch.go1.25/OPENHARMONY_ECS.md |
| ClashBox 主仓库 | https://github.com/xiaobaigroup/ClashBox |
| ClashBox build.sh | https://github.com/xiaobaigroup/ClashBox/blob/master/proxy_core/src/flclash/build.sh |
| ClashBox go.mod | https://github.com/xiaobaigroup/ClashBox/blob/master/proxy_core/src/flclash/go.mod |
| ClashBox .gitmodules | https://github.com/xiaobaigroup/ClashBox/blob/master/.gitmodules |
| gvisor-ohos (魔改 gvisor) | https://github.com/likuai2010/gvisor-ohos |
| ohos-napi (NAPI 绑定) | https://github.com/likuai2010/ohos-napi |
| mihomo core (xfz347 fork) | https://github.com/xfz347/Clash.Meta（未确认：连接超时） |
| DevEco Studio 下载 | https://developer.huawei.com/consumer/cn/deveco-studio/ |

---

## 七、关键注意事项

1. **GOOS 值**：`yourblacksky/ohos_golang_go` 使用 `GOOS=openharmony`（而非 ClashBox build.sh 中的 `GOOS=linux`）。build.sh 中 `GOOS=linux` 是因为 ClashBox 作者使用的是旧版 go-ohos（可能基于更早的 SIG 版本，其 GOOS 仍为 `linux` 但 target 通过 CC 的 `--target=aarch64-linux-ohos` 指定）。新版工具链应该用 `GOOS=openharmony`。

2. **DevEco Studio 的 OHOS Native SDK** 是必需的——它提供 `aarch64-linux-ohos` target 的 clang/llvm 工具链和 sysroot。macOS 上默认路径为 `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native`。

3. **gvisor-ohos** 和 **core (mihomo)** 都是 git submodule，必须 `git submodule update --init --recursive` 拉取。gvisor-ohos 是 `MetaCubeX/gvisor` 的鸿蒙适配分支。

4. **`-tlsmodegd`** 参数（build.sh 中出现）是新版 go-ohos 工具链为支持 ARM64 general-dynamic TLS 引入的编译参数。如果使用 `yourblacksky/ohos_golang_go` 的 Go 1.25.12，可能需要此参数。