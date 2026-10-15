# fds

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | fds |
| 版本 | 6.9.1 |
| 编译器 | gcc@12.3.1 |
| hash | 2jvgrglyco6hibbkit7yev7tleefazps |
| 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/fds-6.9.1-2jvgrgl |
| 主页 | https://pages.nist.gov/fds-smv |

## 描述

Fire Dynamics Simulator (FDS) is a large-eddy simulation (LES) code for

## 鲲鹏优化组件

本软件已链接以下鲲鹏920优化组件：

| 组件 | 功能 |
|------|------|
| hmpi | 鲲鹏优化MPI通信库 |
| hpckit | HPC开发套件元包(编译器+MPI+数学库) |
## 安装命令

```bash
# 加载 spack 环境
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh

# 精确复现本实例（推荐：hash 唯一定位，避免同包多版本/多编译器歧义）
spack install /2jvgrgl

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install fds@6.9.1 gcc@12.3.1

# 加载使用
spack load /2jvgrgl
```

## 依赖树

```
-- linux-openeuler22-aarch64 / %fortran=gcc@12.3.1 --------------
fds@6.9.1
    compiler-wrapper@1.1.0
    gcc@12.3.1
    gcc-runtime@12.3.1
    glibc@2.34
    gmake@4.3
    hmpi@26.0.RC1
        hpckit@26.0.RC1
```

## 加载方式

```bash
spack load /2jvgrgl
```

或通过 module：

```bash
module load fds
```
