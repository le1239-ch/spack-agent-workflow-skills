# su2

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | su2 |
| 版本 | 7.5.1 |
| 编译器 | gcc@12.3.1 |
| hash | z6rrgmln6vm7vwuxpd2fe5bhscb2hrbs |
| 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/su2-7.5.1-z6rrgml |
| 主页 | https://su2code.github.io |

## 描述

SU2 is a suite of open-source software tools written in C++ for the

## 鲲鹏优化组件

本软件已链接以下鲲鹏920优化组件：

| 组件 | 功能 |
|------|------|
| hpckit | HPC开发套件元包(编译器+MPI+数学库) |
| kpblas | 基础线性代数(矩阵乘/向量运算) |
| kplapack | 高级线性代数求解(特征值/SVD) |
## 安装命令

```bash
# 加载 spack 环境
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh

# 精确复现本实例（推荐：hash 唯一定位，避免同包多版本/多编译器歧义）
spack install /z6rrgml

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install su2@7.5.1 gcc@12.3.1

# 加载使用
spack load /z6rrgml
```

## 依赖树

```
-- linux-openeuler22-aarch64 / %c,cxx,fortran=gcc@12.3.1 --------
su2@7.5.1
    compiler-wrapper@1.1.0
    gcc@12.3.1
    gcc-runtime@12.3.1
    glibc@2.34
    meson@1.11.1
        py-pip@26.1.2
        py-setuptools@82.0.1
        py-wheel@0.45.1
        python-venv@1.0
    ninja@1.13.2
        re2c@4.4
            gnuconfig@2024-07-27
    pkgconf@1.8.0
    py-numpy@2.4.6
        kpblas@26.0.RC1
            hpckit@26.0.RC1
        kplapack@26.0.RC1
        py-cython@3.2.4
        py-meson-python@0.19.0
            py-packaging@26.2
                py-flit-core@3.12.0
            py-pyproject-metadata@0.11.0
    py-scipy@1.17.1
        openblas@0.3.30
            compiler-wrapper@1.0
            gcc@12.3.1
            gcc-runtime@12.3.1
        py-pybind11@3.0.2
            cmake@3.22.0
            py-scikit-build-core@0.12.2
                py-hatch-vcs@0.5.0
                    py-setuptools-scm@9.2.2
                        git@2.33.0
                py-hatchling@1.29.0
                    py-pluggy@1.6.0
                    py-trove-classifiers@2026.6.1.19
                        py-calver@2025.10.20
                py-pathspec@1.1.1
        py-pythran@0.18.1
            py-beniget@0.4.2.post1
            py-gast@0.6.0
            py-ply@3.11
    python@3.14.5
        bzip2@1.0.8
            diffutils@3.8
        expat@2.8.1
            libbsd@0.12.2
                libmd@1.1.0
        gdbm@1.26
        gettext@0.21.1
        gmake@4.3
        libffi@3.5.2
        ncurses@6.5-20250705
        openssl@1.1.1wa
        readline@8.3
        sqlite@3.53.1
        util-linux-uuid@2.41
        xz@5.6.3
        zstd@1.5.7
    zlib@1.2.11
```

## 加载方式

```bash
spack load /z6rrgml
```

或通过 module：

```bash
module load su2
```
