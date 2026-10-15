# roms

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | roms |
| 版本 | 4.2 |
| 编译器 | gcc@12.3.1 |
| hash | xq4bdvxyjkyg4agck2ovk4j64oo6dixs |
| 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/roms-4.2-xq4bdvx |
| 主页 | https://www.myroms.org/ |

## 描述

ROMS is a free-surface, terrain-following, primitive equations ocean

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
spack install /xq4bdvx

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install roms@4.2 gcc@12.3.1

# 加载使用
spack load /xq4bdvx
```

## 依赖树

```
-- linux-openeuler22-aarch64 / %c,fortran=gcc@12.3.1 ------------
roms@4.2
    compiler-wrapper@1.1.0
    curl@7.79.1
    gcc@12.3.1
    gcc-runtime@12.3.1
    glibc@2.34
    gmake@4.3
    hdf5@1.14.6
        cmake@3.31.9
            compiler-wrapper@1.0
            gcc@12.3.1
            gcc-runtime@12.3.1
            ncurses@6.5-20250705
        pkgconf@1.8.0
    hmpi@26.0.RC1
        hpckit@26.0.RC1
    netcdf-c@4.10.0
        bzip2@1.0.8
            diffutils@3.8
        c-blosc@1.21.6
            lz4@1.10.0
            snappy@1.2.1
        gnuconfig@2024-07-27
        libaec@1.1.4
        zstd@1.5.7
    netcdf-fortran@4.6.2
    zlib@1.2.11
```

## 加载方式

```bash
spack load /xq4bdvx
```

或通过 module：

```bash
module load roms
```
