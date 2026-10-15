# swan

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | swan |
| 版本 | 4145 |
| 编译器 | llvm@19.1.7 |
| hash | yjxoulhtnf37wp5yhkfh7k6r5gxeok7k |
| 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/swan-4145-yjxoulh |
| 主页 | https://swanmodel.sourceforge.net/ |

## 描述

SWAN is a third-generation wave model, developed at Delft University of

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
spack install /yjxoulh

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install swan@4145 llvm@19.1.7

# 加载使用
spack load /yjxoulh
```

## 依赖树

```
-- linux-openeuler22-aarch64 / %fortran=clang@19.1.7 ------------
swan@4145
    compiler-wrapper@1.1.0
    glibc@2.34
    gmake@4.3
    hmpi@26.0.RC1
        hpckit@26.0.RC1
    llvm@19.1.7
    netcdf-fortran@4.6.2
        gmake@4.3
        gnuconfig@2024-07-27
        netcdf-c@4.10.0
            bzip2@1.0.8
                compiler-wrapper@1.0
                diffutils@3.8
                gcc@12.3.1
                gcc-runtime@12.3.1
            c-blosc@1.21.6
                cmake@3.31.9
                    curl@7.79.1
                    ncurses@6.5-20250705
                lz4@1.10.0
                snappy@1.2.1
            hdf5@1.14.6
                cmake@3.22.0
                pkgconf@1.8.0
            libaec@1.1.4
            zlib@1.2.11
            zstd@1.5.7
    perl@5.34.0
```

## 加载方式

```bash
spack load /yjxoulh
```

或通过 module：

```bash
module load swan
```
