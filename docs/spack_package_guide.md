# Spack package.py 编写精简指南

> 提取自 spack-new-package skill，仅保留 stage3 编写 package.py 时最常用的内容。

## 1. 判断构建系统

```bash
git clone --depth 1 <repo_url> /tmp/<pkg>
cd /tmp/<pkg>
ls CMakeLists.txt        # → CMakePackage
ls configure*            # → AutotoolsPackage
ls Makefile              # → MakefilePackage
ls setup.py pyproject.toml  # → PythonPackage
ls meson.build           # → MesonPackage
```

## 2. 基类与导入

| 构建系统 | 基类 | 导入 |
|---------|------|------|
| CMake | CMakePackage | `from spack_repo.builtin.build_systems.cmake import CMakePackage` |
| Autotools | AutotoolsPackage | `from spack_repo.builtin.build_systems.autotools import AutotoolsPackage` |
| Makefile | MakefilePackage | `from spack_repo.builtin.build_systems.makefile import MakefilePackage` |
| Meson | MesonPackage | `from spack_repo.builtin.build_systems.meson import MesonPackage` |
| 无/自定义 | Package | `from spack_repo.builtin.build_systems.generic import Package` |

## 3. HPCKit 头部模板（双编译器 gcc/bisheng）

```python
import os, shutil
from spack_repo.builtin.build_systems.generic import Package
from spack.package import *

class PkgNameOpt(Package):
    """一句话描述。"""
    homepage = "https://..."
    url = "https://.../pkg-x.y.z.tar.gz"
    license("Apache-2.0")
    version("x.y.z", sha256="<sha256>")

    depends_on("c", type="build")
    depends_on("cxx", type="build")
    depends_on("hpckit", type="build")
    depends_on("hmpi compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
    depends_on("hmpi compiler_variant=gcc", when="%gcc", type=("build","link","run"))

    # KML 数学库（按需选）
    depends_on("kpkml compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
    depends_on("kpkml compiler_variant=gcc", when="%gcc", type=("build","link","run"))

    def _compiler_variant(self):
        if self.spec.satisfies("%llvm"):
            return "bisheng"
        return "gcc"

    def _get_compiler_prefix(self):
        return join_path(
            self.spec["hpckit"].prefix, "HPCKit",
            str(self.spec["hpckit"].version), "compiler", self._compiler_variant())
```

## 4. HPCKit 目录布局

```
<hpckit_prefix>/HPCKit/<version>/
├── compiler/
│   ├── bisheng/{bin,lib}
│   └── gcc/{bin,lib64,lib64_public}
├── hmpi/
│   ├── bisheng/release/hmpi/{bin,lib,include}
│   └── gcc/release/hmpi/{bin,lib,include}
└── kml/
    ├── bisheng/{include,lib}
    └── gcc/{include,lib}
```

## 4.1 鲲鹏数学库及优化组件参考（14个包）

从 kp-spack 仓库拉取的鲲鹏优化包，在 package.py 中通过 `depends_on` 声明：

| 类别 | 包名 | 替换的开源等价物 | 功能 | depends_on 示例 |
|------|------|-----------------|------|-----------------|
| MPI | `hmpi` | OpenMPI | 鲲鹏优化MPI通信库 | `depends_on("hmpi compiler_variant=gcc", when="%gcc")` |
| 套件 | `hpckit` | — | HPC开发套件元包 | `depends_on("hpckit", type="build")` |
| BLAS | `kpblas` | OpenBLAS | 基础线性代数 | `depends_on("kpkml compiler_variant=gcc", when="%gcc")` |
| | `kpspblas` | — | 稀疏矩阵BLAS | ↑ 通过 kpkml 元包拉入 |
| LAPACK | `kplapack` | LAPACK | 高级线性代数求解 | ↑ 通过 kpkml 元包拉入 |
| | `kpscalapack` | ScaLAPACK | 分布式并行LAPACK | ↑ 通过 kpkml 元包拉入 |
| | `kpscasolver` | — | 分布式求解器 | ↑ 通过 kpkml 元包拉入 |
| | `kpsolver` | — | 直接求解器 | ↑ 通过 kpkml 元包拉入 |
| FFT | `kpfft` | FFTW | 快速傅里叶变换 | ↑ 通过 kpkml 元包拉入 |
| | `kpfftw` | FFTW | FFTW接口兼容层 | ↑ 通过 kpkml 元包拉入 |
| 向量 | `kpvml` | — | 向量数学函数库 | ↑ 通过 kpkml 元包拉入 |
| | `kpksvml` | — | 短向量数学函数库 | ↑ 通过 kpkml 元包拉入 |
| 其他 | `kpkupl` | — | 鲲鹏通用性能库 | ↑ 通过 kpkml 元包拉入 |
| | `kpkml` | — | KML元包（聚合上述子库） | `depends_on("kpkml compiler_variant=gcc", when="%gcc")` |

> **常用做法**：直接 `depends_on("kpkml ...")` 即可拉入全部 KML 子组件，无需逐个声明。`hmpi` 和 `hpckit` 需单独声明。

## 5. 环境注入

```python
def setup_build_environment(self, env):
    spec = self.spec
    cp = self._get_compiler_prefix()
    cv = self._compiler_variant()
    # 编译器运行时库
    if cv == "gcc":
        env.prepend_path("LD_LIBRARY_PATH", join_path(cp, "lib64_public"))
        env.prepend_path("LD_LIBRARY_PATH", join_path(cp, "lib64"))
    else:
        env.prepend_path("LD_LIBRARY_PATH", join_path(cp, "lib"))
    # hmpi
    hmpi = spec["hmpi"]
    if hmpi.libs:
        env.prepend_path("LD_LIBRARY_PATH", hmpi.libs.directories[0])
    env.set("CC", hmpi.mpicc)
    env.set("CXX", hmpi.mpicxx)
    env.set("FC", hmpi.mpifc)

def setup_run_environment(self, env):
    # 同 setup_build_environment + 可执行文件 PATH
    env.prepend_path("PATH", self.prefix.bin)
```

## 6. CMake 项目典型实现

```python
def cmake_args(self):
    args = []
    args.append(self.define_from_variant("ENABLE_MPI", "mpi"))
    return args
```

## 7. Generic Package（手动 configure + make）

```python
phases = ["configure", "build", "install"]

def configure(self, spec, prefix):
    mkdirp("build")
    with working_dir("build"):
        cmake = which("cmake")
        cmake("..", "-DCMAKE_INSTALL_PREFIX={0}".format(prefix))

def install(self, spec, prefix):
    with working_dir("build"):
        make = which("make")
        make("-j{0}".format(make_jobs), "install")
```

## 8. 包名规则

- 仓库子目录名用下划线 `_`：`packages/my_pkg_opt/`
- spec 字符串用连字符 `-`：`spack install my-pkg-opt`
- Python 类名用驼峰：`class MyPkgOpt(Package)`

## 9. 本地仓库使用

本地 repo 在 stage3 由 `create_local_repo` 创建（基于 CPU 型号命名，如 `kunpeng920F-repo`），并注册到 spack `repos.yaml`。

```bash
# 获取本地 repo 路径（自动从 repos.yaml 或 env_report.md 读取）
source ${WORKFLOW_ROOT}/scripts/lib_common.sh
LOCAL_REPO=$(get_local_repo_path)

# 创建 package 目录
mkdir -p ${LOCAL_REPO}/packages/my_pkg_opt

# 写 package.py 到 packages/my_pkg_opt/package.py

# repo 已在 repos.yaml 中注册，无需 spack repo add
spack repo list
spack info my-pkg-opt    # 验证

# 安装
spack spec my-pkg-opt %gcc
spack install my-pkg-opt %gcc
```

## 10. HPCKit 编译器环境加载

```bash
# GCC 版本（进入 hpckit 安装目录）
HPCKIT_PREFIX=$(spack location -i hpckit)
HPCKIT_VER=$(ls ${HPCKIT_PREFIX}/HPCKit/ | head -1)
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER}
source setvars.sh --use-gcc    # 加载 GCC + HMPI + KML

# BiSheng 版本
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER}
source setvars.sh              # 加载 BiSheng + HMPI + KML
```

## 11. 手动编译安装（spack 无包时的 fallback）

当软件不在 spack builtin 和 kunpeng920prof repo 中时：

```bash
# 1. 在 spack-workflow 下创建目录
mkdir -p $SPACK_WORKFLOW_DIR/manual-build/<pkg_name>
cd $SPACK_WORKFLOW_DIR/manual-build/<pkg_name>

# 2. 加载 HPCKit 环境
HPCKIT_PREFIX=$(spack location -i hpckit)
HPCKIT_VER=$(ls ${HPCKIT_PREFIX}/HPCKit/ | head -1)
source ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER}/setvars.sh --use-gcc

# 3. 下载源码
wget <source_url>
tar -xzf <source>.tar.gz && cd <source>

# 4. 编译安装（根据构建系统）
./configure --prefix=$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install
make -j$(nproc) && make install

# 或 CMake:
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install
make -j$(nproc) && make install
```

## 12. 已知坑速查

| 坑 | 规避 |
|----|------|
| hmpi 缺 OMPI_CC 注入 | 消费者包自行设 `OMPI_CC=spack_cc` |
| spack compiler-wrapper 静默禁用 SVE | 绕过 wrapper：`CC`/`CXX` 设为 HPCKit gcc 绝对路径（实测修复后 100+ SVE 指令） |
| -flto 禁用 SVE 向量化 | 不要加 -flto |
| -ffast-math 破坏浮点收敛 | GCC 默认 FP 语义最优 |
| 包名含 `-` 的 libs 失败 | 用 `spec["pkg-opt"].prefix` 拼路径 |
| KML stdout 警告污染 meson | meson native file 提供 external property |
| vendor config.guess 不支持 aarch64 | 用 gnuconfig 替换 |
