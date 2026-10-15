---
name: spack-new-package
description: 面向 HPCKit 生态的 Spack package.py 开发完整指南，覆盖 bisheng/gcc 双编译器、hmpi、HPCKit 优化库（kpblas/kpfft/kpkml 等计算库系列），以及通用 Spack 语法与全构建系统支持
---

# HPCKit 生态 + Spack package.py 开发完整指南

## 触发场景

用户需要在 HPCKit 生态下编写 Spack package.py，包括但不限于：
- 依赖 HPCKit 编译器（bisheng / gcc 双变体）与 hmpi 的 C/C++/Fortran 项目
- 需要将 HPC/科学计算软件打包为 Spack 包并接入 HPCKit 工具链
- 含 vendor 子项目（htslib 等）需要 autotools 改造与 gnuconfig 替换
- 需要改 CMakeLists.txt / 源文件（OpenMP、aarch64 适配、MPI find_package 注入）
- 需要在构建期与运行期都注入编译器、MPI、HDF5 等环境
- 需要为非标准构建系统（原生 Makefile、csh 脚本等）编写安装脚本
- 需要在本地 Spack 仓库中创建新包
- 依赖 HPCKit 计算库系列（kpblas/kpfft/kpkml 等）的数值计算项目
- 手工编译/调试应用时需要选对 KML 指令集变体目录（neon/sve/sve512/sve_no_f64mm/sme=matrix），或排查「KML 算出来的数不对但程序不报错」

## 工作流程总览

```
1. 分析软件源码构建系统
2. 选择合适的 Spack 基类
3. 确定 HPCKit 生态依赖与双变体策略
4. 声明版本、变体、依赖
5. 编写构建逻辑（含 HPCKit 环境注入）
6. 处理 patch 与常见构建问题
7. 配置运行时环境
8. 本地仓库注册与验证
```

---

## 阶段一：分析软件构建系统

### 需要确认的信息

```bash
# 克隆源码到临时目录
git clone --depth 1 <repo_url> /tmp/<pkg_name>
```

逐项检查：

| 检查项 | 命令/文件 | 分类依据 |
|--------|----------|---------|
| CMakeLists.txt 存在？ | `ls CMakeLists.txt` | → CMakePackage |
| configure / configure.ac 存在？ | `ls configure*` | → AutotoolsPackage |
| Makefile 存在？ | `ls Makefile` | → MakefilePackage |
| setup.py / pyproject.toml？ | `ls setup.py pyproject.toml` | → PythonPackage |
| meson.build 存在？ | `ls meson.build` | → MesonPackage |
| 仅 .py 脚本（无 setup.py）？ | `ls *.py` 且无 setup.py | → Package (Generic) + pip + wrapper |
| 版本号/标签 | `git tag -l` | 确定版本声明 |
| 编程语言 | 看源文件后缀 | 确定语言依赖 |
| 外部依赖 | 看 Makefile/CMakeLists/imports | 确定 depends_on |
| 并行构建安全？ | 看 Fortran .mod 依赖链 | 确定 parallel 设置 |

### 构建系统配置机制

对于非标准构建系统，额外确认：
- 编译器/链接器如何被指定（环境变量？配置文件？命令行参数？）
- 预处理器宏（CPP flags）的传递方式
- 平台/架构相关配置如何选择

### CMake 项目额外检查

对于 CMake 项目，还需确认：
- 是否有 `install()` 规则？（`grep -n 'install' CMakeLists.txt`）— 若无，需自定义 install 阶段
- 是否无条件 `add_subdirectory()` 引入 examples/tests？— 这些子目录可能引入额外依赖（如 TBB），需通过 `patch()` 移除
- 构建产物类型（可执行文件 / 静态库 / 动态库）及其在构建目录中的位置

### HPCKit 生态额外检查

- 是否需要 MPI？→ 使用 hmpi（HPCKit 自带的 MPI 实现）
- 是否需要 HDF5？→ 使用 hdf5-opt（HPCKit 优化版）
- 是否需要在 aarch64（鲲鹏）上运行？→ 检查 x86 硬编码标志
- vendor 子项目的 config.guess/config.sub 是否支持 aarch64？

---

## 阶段二：选择基类与导入

### 基类对应关系

| 构建系统 | 基类 | 导入路径 | 构建阶段 |
|---------|------|---------|---------|
| CMake | CMakePackage | `spack_repo.builtin.build_systems.cmake` | cmake → build → install |
| Autotools | AutotoolsPackage | `spack_repo.builtin.build_systems.autotools` | autoreconf → configure → build → install |
| Makefile | MakefilePackage | `spack_repo.builtin.build_systems.makefile` | edit → build → install |
| Python (setup.py/pyproject.toml) | PythonPackage | `spack_repo.builtin.build_systems.python` | build → install |
| Meson | MesonPackage | `spack_repo.builtin.build_systems.meson` | meson → build → install |
| 无/自定义 | Package | `spack_repo.builtin.build_systems.generic` | install |
| Python 脚本（无 setup.py） | Package | `spack_repo.builtin.build_systems.generic` | install（含 pip + wrapper） |

### 标准头部模板（通用）

```python
from spack_repo.builtin.build_systems.<system> import <BaseClass>

from spack.package import *


class PkgName(BaseClass):
    """一句话描述软件功能。"""

    homepage = "https://..."
    url = "https://..."         # tar.gz 下载地址
    git = "https://..."         # 或 git 仓库地址（二选一即可）

    license("Apache-2.0")       # 可选：SPDX 许可证标识符
```

**注意：** `Package` 基类也通过 `from spack.package import *` 导出，因此 Generic Package 可以省略 `from spack_repo.builtin.build_systems.generic import Package` 这行导入。但推荐显式导入以提高可读性。需要 `os`、`shutil` 等标准库时在文件顶部额外导入。

### HPCKit 生态头部模板

HPCKit 生态包通常用 `Package` (Generic) 基类，自定义 phases：

```python
import os
import shutil

from spack_repo.builtin.build_systems.generic import Package

from spack.package import *


class PkgNameOpt(Package):
    """一句话描述软件功能（HPCKit 优化版）。"""

    homepage = "https://..."
    url = "https://.../pkg-x.y.z.tar.gz"

    license("<SPDX>")

    version("x.y.z", sha256="<sha256>")

    # 语言依赖
    depends_on("c", type="build")
    depends_on("cxx", type="build")

    # HPCKit 生态依赖
    depends_on("hpckit", type="build")
    depends_on("hmpi compiler_variant=bisheng", when="%llvm",
               type=("build", "link", "run"))
    depends_on("hmpi compiler_variant=gcc", when="%gcc",
               type=("build", "link", "run"))
    depends_on("hdf5-opt@1.12.1")
    depends_on("gnuconfig", type="build")
    depends_on("zlib-api", type=("build", "link"))

    # vendor 子项目走 autoheader && autoconf
    depends_on("autoconf", type="build")
    depends_on("automake", type="build")
    depends_on("libtool", type="build")
    depends_on("m4", type="build")
    depends_on("gmake", type="build")

    # patch 文件（惯例：放在 depends_on 之后）
    patch("file1.patch", when="@x.y.z", level=1)

    phases = ["edit", "configure", "install"]
    parallel = False  # vendor 子库要先编出来再被主项目链接
```

### license() 声明

可选但推荐，使用 SPDX 标准许可证标识符：

```python
license("Apache-2.0")
license("GPL-2.0-or-later")
license("MIT")
```

---

## 阶段三：HPCKit 生态特有配置

### HPCKit 目录布局

```
<hpckit_prefix>/HPCKit/<version>/
├── compiler/
│   ├── bisheng/{bin,lib}              # bisheng 编译器与运行时库
│   └── gcc/{bin,lib64,lib64_public}   # gcc 编译器与运行时库
└── hmpi/
    ├── bisheng/release/hmpi/{bin,lib,include}   # bisheng 版 hmpi
    └── gcc/release/hmpi/{bin,lib,include}        # gcc 版 hmpi
```

### 双变体编译器路径

参考 `hdf5-opt` 的双变体风格：

```python
def _compiler_variant(self):
    if self.spec.satisfies("%llvm"):
        return "bisheng"
    return "gcc"

def _get_compiler_prefix(self):
    hpckit_prefix = self.spec["hpckit"].prefix
    hpckit_ver = str(self.spec["hpckit"].version)
    return join_path(
        hpckit_prefix, "HPCKit", hpckit_ver,
        "compiler", self._compiler_variant(),
    )
```

### hmpi 的 spec 属性

`hmpi/package.py` 显式定义了这些属性，可直接用：

| 属性 | 来源 |
|------|------|
| `hmpi.mpicc` / `mpicxx` / `mpifc` / `mpif77` / `mpif90` | `setup_dependent_package` 里赋值 |
| `hmpi.libs` | `find_libraries(["libmpi"], hmpi_prefix/lib, shared=True)` |
| `hmpi.headers` | `find_headers(["mpi"], hmpi_prefix/include)` |

### 包名带 `-` 的 libs/headers 陷阱

spack 默认 `libs` 属性按包名找库：包名 `hdf5-opt` 会被替换成 `libhdf5?opt`（`-` 当通配符），但实际库是 `libhdf5.so`，匹配不到，触发：

```
==> Error: Unable to recursively locate hdf5-opt libraries in ...
```

**规避方式：** 直接用 `spec["pkg-opt"].prefix` 拼 `lib`/`include`/`bin` 路径，**不要**用 `spec["pkg-opt"].libs` / `.headers`：

```python
# 错：会触发 NoLibrariesError
hdf5 = spec["hdf5-opt"]
if hdf5.libs:
    env.prepend_path("LD_LIBRARY_PATH", hdf5.libs.directories[0])

# 对：直接拼路径
hdf5_prefix = spec["hdf5-opt"].prefix
env.prepend_path("LD_LIBRARY_PATH", join_path(hdf5_prefix, "lib"))
```

| 包名 | `libs`/`headers` 是否安全 | 原因 |
|------|--------------------------|------|
| `hdf5-opt`（含 `-`） | 不安全 | 默认找 `libhdf5?opt` 匹配不到 `libhdf5.so` |
| `hmpi`（无 `-`） | 安全 | 且 `hmpi/package.py` 显式定义了 `find_libraries(["libmpi"], ...)` |
| 任何含 `-` 的包名 | 不安全 | spack 把 `-` 当 glob `?` |

### HPCKit 计算库系列依赖

HPCKit 内置一组数学库（KML 系列），已封装为 Spack 包，**都内置 `compiler_variant` variant**（`gcc`/`bisheng`）区分对应编译器的库版本。在新开发的 package.py 里直接通过 `%llvm`/`%gcc` 条件声明即可，**不要写死版本，也不需要让用户手动指定 `compiler_variant`**：

| 包名 | 提供的库 / 虚拟包 |
|------|------------------|
| `hpckit` | 编译器与 hmpi 的元依赖（不直接提供库） |
| `hmpi` | `provides("mpi")` |
| `kpblas` | `provides("blas")`，libkblas |
| `kplapack` | `provides("lapack")` |
| `kpfftw` | `provides("fftw-api@3")` |
| `kpfft` | FFT 库 |
| `kpksvml` | SVE 向量数学库 |
| `kpvml` | VML 向量数学库 |
| `kpkml` | **聚合包**，一次性拉入 kpblas+kpfft+kpksvml+kpvml+kplapack 并自动注入 KML 通用 lib/noarch 路径（libkm.so 所在） |
| `kpkupl` | KUPL 通信库（用于 LAMMPS 等） |
| `kpscalapack` | `provides("scalapack")`，依赖 mpi |
| `kpscasolver` | ScaLAPACK 求解器，依赖 mpi |
| `kpsolver` | 求解器 |
| `kpspblas` | 并行 BLAS |
| `kscalapack` | 独立 scalapack（不依赖 hpckit，只依赖 mpi） |

#### 标准依赖声明写法

```python
# 单个计算库（按需选择）
depends_on("kpblas compiler_variant=bisheng", when="%llvm",
           type=("build", "link", "run"))
depends_on("kpblas compiler_variant=gcc", when="%gcc",
           type=("build", "link", "run"))

# 聚合包 kpkml（推荐，一次拉全套 KML）
depends_on("kpkml compiler_variant=bisheng", when="%llvm",
           type=("build", "link", "run"))
depends_on("kpkml compiler_variant=gcc", when="%gcc",
           type=("build", "link", "run"))
```

#### 为什么不写死版本

- 这些 kp* 包本身已通过 `depends_on("hpckit@26.0.RC1", when="@26.0.RC1")` 等约束保证与 hpckit 版本匹配
- 在新 package.py 里再加 `@26.0.RC1` 会重复约束，并阻止用户通过 `^hpckit@25.1.0` 切换版本
- 正确做法：让用户安装时通过 `^hpckit@<ver>` 指定版本，kp* 会自动跟随

```bash
# 用户安装时指定版本
spack install psipred-opt %gcc ^hpckit@26.0.RC1
spack install lammps-kml %gcc ^hpckit@25.1.0
```

#### 为什么用 `when="%llvm"`/`when="%gcc"` 而非 `compiler_variant=`

- `compiler_variant` variant 是 kp* 包**内部**用来区分库路径的，不应暴露给最终用户
- 用户只需选编译器（`%gcc`/`%llvm`），由 package.py 自动映射到对应 `compiler_variant`
- 这样也避免了用户忘记指定 `compiler_variant` 导致路径错乱

#### KML 库内部结构与合并分析

KML 的 BLAS（libkblas.so）是闭源二进制，只有 .so 没有 .a；LAPACK 分 libklapack.a（仅优化函数）和 libklapack_full.so（含 Netlib 参考实现）。`libklapack_full.so` 中 BLAS 符号为 U（未定义），运行时从 libkblas.so 解析。因此**无法像 OpenBLAS 那样合成单个 .so**（GNU ld 默认不搜索传递 NEEDED 依赖）。详见 `references/kml-library-structure-and-merging.md`（含符号依赖表、4 种合并方案失败原因、ifunc trampoline 可行方案、OMP_5.0.1 libgomp 版本坑）。

#### 不要修改 kp* 包本身

这些 kp* 系列包是基础设施数学库的封装，已经过验证。新开发的 package.py 只作为它们的**消费者**，不能修改 kp* 包本身的脚本。

#### 聚合包 kpkml 的特点

`kpkml` 是聚合包,会一次性拉入 `kpblas`/`kpfft`/`kpksvml`/`kpvml`/`kplapack` 全套 KML 子组件,并通过 `setup_dependent_build_environment` 注入 `kml/<variant>/lib` 和 `lib/noarch` 到 `LIBRARY_PATH`。`kpblas` 还会根据 `/proc/cpuinfo` 自动检测 neon/sve/sme 子目录。

**根据实际依赖情况选择**,不要盲目用聚合包:
- 只需要单个库(如只需要 BLAS) → 用 `depends_on("kpblas ...")`
- 需要多个 KML 库 → 逐个声明,或按需用 `kpkml` 聚合包
- `kpkml` 会拉入**所有**KML 子组件,如果只需要一两个库,用聚合包会增加不必要的依赖

#### kpkml 的 KML 目录布局

```
<hpckit_prefix>/HPCKit/<version>/kml/<compiler_variant>/
├── include/                  # KML 公共头文件
└── lib/
    ├── libkml_rt.so           # KML 单体运行时（按 CPU dlopen 挑子目录；无库 DT_NEEDED 它）
    ├── noarch/                # 与 ISA 无关：libkm.so / libkvsl / libkes / libfftw3 / libklapack_full ...
    ├── neon/kblas/<mode>/      # neon 版 libkblas（part 0xd01）
    ├── sve/kblas/<mode>/       # sve(256bit) 版 libkblas + kfft（part 0xd02/0xd03）
    ├── sve_no_f64mm/           # 只有 KFFT 家族；part 0xd06 缺 F64MM 时用
    ├── sve512/                 # part 0xd22：klapack / kscalapack / ksolver / kspblas / kfft*（注意：无 kblas）
    └── sme/kblas/<mode>/       # part 0xd22 的 KBLAS（SME 矩阵扩展）；26.1.RC1 起目录改名 matrix/
```

`<mode>` 是 kpblas 的 `kblas_mode` variant，取值 `multi`/`locking`/`nolocking`（默认 `multi`）。
选哪个 ISA 目录由 `kml/<variant>/env/setvars.sh` / `modulefiles/kml` 按 `/proc/cpuinfo` 的 CPU part 决定
（0xd01→neon，0xd02/0xd03→sve，0xd06→sve+`sve_no_f64mm` 的 KFFT，0xd22→`sve512` + kblas 取 `matrix`/`sme`）。

⚠ **这些变体是按固定 SVE/SME 向量长度编译的，运行时 per-thread VL 不匹配会「静默算错」而非报错**：
0xd22 的 `matrix`/`sme` KBLAS 假定 SME VL=512bit，而内核默认只有 256bit，必须在**每个 OpenMP 线程**里
`prctl(PR_SME_SET_VL, 64)`；`sve/` 版库在 512bit 机器上则需把 VL 设成 256bit。
目录差异、VL 实测数据、链接坑（`libklapack_full`、`libgomp` OMP 5.0.1、同名库按 LD_LIBRARY_PATH 顺序取胜）、
实测性能与可复现验证配方见 `references/kml-isa-variants.md`。

#### 在 edit phase 引用 kpblas 库路径

如果项目（如 psipred）的 Makefile 写死了 `-lkblas -lkm`，需要在 edit phase 显式提供 `-L` 路径：

```python
def edit(self, spec, prefix):
    # 通过 kpblas.libs 获取自动检测 ISA 后的库目录
    kblas_libs = spec["kpblas"].libs
    kblas_lib_dir = kblas_libs.directories[0] if kblas_libs else ""

    # libkm 在 kml/<variant>/lib/noarch 下
    kml_lib_dir = join_path(
        spec["hpckit"].prefix, "HPCKit",
        str(spec["hpckit"].version), "kml",
        self._compiler_variant(), "lib",
    )

    libs = "-L{0} -lkblas -L{1} -lkm -lm".format(
        kblas_lib_dir, join_path(kml_lib_dir, "noarch"),
    )
    # 写入 Makefile...
```

---

## 阶段四：声明版本

### URL 源码包方式

```python
version("1.2.3", sha256="...")
version("1.2.3", sha256="...", url="https://...")  # 非标准 URL
```

获取 sha256：
```bash
curl -sL <url> | sha256sum
```

### Git 方式

```python
version("master", branch="master")
version("2.3.01", tag="2.3.01")
version("2.3.01", commit="abc123...")
version("2.3.01", tag="2.3.01", commit="abc123...", submodules=True)  # 含子模块
```

**submodules=True**：当项目依赖 git 子模块（如 TVM 的第三方库、Cactus 的 sonLib/HAL 等），必须添加此参数，否则克隆的源码不完整，构建会失败。

**get_full_repo=True**：当项目有大量子模块且子模块使用相对 URL 时（如 Rosetta 的 `../../RosettaCommons/binder.git`），需要完整克隆以确保 git 能正确解析相对路径引用的子模块提交。

### resource() 获取额外源码

当软件依赖一个独立的 git 仓库（如捆绑依赖包），使用 `resource()` 在获取主源码的同时获取额外源码：

```python
resource(
    name="copasi-dependencies",
    git="https://github.com/copasi/copasi-dependencies.git",
    tag="v4.29.228",
    commit="c7fcc6c6c4169297704c5b803794db905bcc78f1",
    destination="",
    placement="copasi-dependencies",
    submodules=True,
)
```

**参数说明：**
- `destination=""` — 资源解压到 stage 根目录
- `placement="copasi-dependencies"` — 解压后的目录名
- 在 `build()` 中通过 `join_path(self.stage.source_path, "copasi-dependencies")` 访问

---

## 阶段五：声明 Variants（可选特性）

```python
# 布尔型
variant("mpi", default=True, description="Enable MPI support")

# 多选型
variant("eos", default="sig2", values=("sig0", "sig2"),
        description="Equation of state type")

# 条件约束
variant("cuda", default=False, description="CUDA support", when="@2.0:")
```

---

## 阶段六：声明依赖

### 语言依赖

**注意：** CMake 项目即使只用 C++，也必须声明 `depends_on("c", type="build")`，因为 CMake 会自动探测 C 编译器。缺少此声明会导致 `SPACK_CC_* variables not set` 错误。

```python
depends_on("c", type="build")       # CMake 项目必须声明，即使是纯 C++ 项目
depends_on("cxx", type="build")
depends_on("fortran", type="build")
```

### 外部库依赖（通用）

```python
depends_on("mpi", when="+mpi")
depends_on("hdf5+mpi", when="+hdf5+mpi")
depends_on("gmake", type="build")
depends_on("cmake@3.16:", type="build")
```

type 取值说明：
- `"build"` — 仅构建时需要
- `"link"` — 链接时需要（默认包含）
- `"run"` — 运行时需要
- `"test"` — 测试时需要

### HPCKit 生态依赖

HPCKit 生态下，每条 `module load` 对应一个 `depends_on`：

```python
# HPCKit 工具链
depends_on("hpckit", type="build")

# hmpi（双变体，按编译器区分）
depends_on("hmpi compiler_variant=bisheng", when="%llvm",
           type=("build", "link", "run"))
depends_on("hmpi compiler_variant=gcc", when="%gcc",
           type=("build", "link", "run"))

# HPCKit 优化库
depends_on("hdf5-opt@1.12.1")

# 其他常见 HPCKit 依赖
depends_on("zlib-api", type=("build", "link"))
```

### vendor 子项目的 autotools 依赖

当软件包含 vendor 子项目（如 htslib）需要 autotools 重新生成配置脚本时：

```python
depends_on("gnuconfig", type="build")
depends_on("autoconf", type="build")
depends_on("automake", type="build")
depends_on("libtool", type="build")
depends_on("m4", type="build")
depends_on("gmake", type="build")
```

---

## 阶段七：编写构建逻辑

### CMakePackage 典型实现

```python
def cmake_args(self):
    args = []
    args.append(self.define_from_variant("ENABLE_MPI", "mpi"))
    args.append(self.define("CMAKE_C_COMPILER", self.spec["mpi"].mpicc))
    return args
```

### CMakePackage 禁用可选依赖

当 CMake 项目通过 `find_package()` 检测可选依赖（如 OpenMP、CUDA）时，使用 `CMAKE_DISABLE_FIND_PACKAGE_<PkgName>` 模式禁用：

```python
def cmake_args(self):
    args = [
        self.define_from_variant("BUILD_TESTS", "tests"),
    ]
    if "~openmp" in self.spec:
        args.append(self.define("CMAKE_DISABLE_FIND_PACKAGE_OpenMP", True))
    return args
```

### CMakePackage 缺失显式依赖发现逻辑时的补救

有些上游 CMake 项目源码会直接 `#include` 外部头文件（如 `fftw3.h`），但 `CMakeLists.txt` 里既没有 `find_package()`，也没有把对应 include 目录加入 target。此时即使 Spack 里声明了 `depends_on("fftw")`，编译仍可能报头文件找不到。

处理顺序建议：
1. 先补 `depends_on()`，确保依赖被 concretize 和安装
2. 再用 `setup_build_environment()` 注入 include/lib 搜索路径
3. 如果上游完全不消费环境变量，再用 `cmake_args()` 直接追加 `CMAKE_CXX_FLAGS`

```python
depends_on("fftw")

def cmake_args(self):
    return [
        self.define(
            "CMAKE_CXX_FLAGS",
            "-isystem {0}".format(self.spec["fftw"].prefix.include),
        )
    ]

def setup_build_environment(self, env):
    env.prepend_path("CPLUS_INCLUDE_PATH", self.spec["fftw"].prefix.include)
    env.prepend_path("C_INCLUDE_PATH", self.spec["fftw"].prefix.include)
    env.prepend_path("LIBRARY_PATH", self.spec["fftw"].prefix.lib)
```

**典型信号：** 构建日志里出现 `fatal error: fftw3.h: No such file or directory`，但 `spack spec` 已经能看到 `fftw` 在依赖树中。

### CMakePackage 无 install 规则时的自定义安装

许多 CMake 项目（尤其是库项目）没有定义 `install()` 规则，此时需覆写 `install()` 方法手动安装产物：

```python
def install(self, spec, prefix):
    source = self.stage.source_path
    build_dir = self.build_directory

    mkdirp(prefix.lib)
    lib_file = find(build_dir, "libfoo.a", recursive=True)
    if lib_file:
        install(lib_file[0], prefix.lib)

    install_tree(join_path(source, "src"), prefix.include)

    if os.path.isdir(join_path(source, "examples")):
        install_tree(join_path(source, "examples"), prefix.share.examples)
```

**注意：** 覆写 `install()` 后 CMake 不再执行默认的 `cmake --install`，因此必须手动处理所有需要安装的产物。

### CMakePackage 通过 patch() 移除不需要的子目录

当 CMakeLists.txt 无条件引入 examples/tests 等子目录，而这些子目录可能引入额外依赖时，使用 `patch()` 移除：

```python
def patch(self):
    import re

    cmakelists = join_path(self.stage.source_path, "CMakeLists.txt")
    with open(cmakelists, "r") as f:
        content = f.read()
    content = re.sub(r"add_subdirectory\(examples/[^\)]*\)\n?", "", content)
    content = re.sub(r"add_subdirectory\(utility/[^\)]*\)\n?", "", content)
    with open(cmakelists, "w") as f:
        f.write(content)
```

### CMakePackage 禁用测试后残留测试目标的修补

有些上游项目即使设置了 `BUILD_TESTS=OFF`，仍会在其他子目录里无条件调用 `add_dependencies(TestFoo ...)`。需在 `patch()` 里把残留的 target 引用删掉：

```python
def patch(self):
    test_cmake = join_path(self.stage.source_path, "heart", "CMakeLists.txt")
    filter_file(r"add_dependencies\(TestFoo[^\)]*\)", "", test_cmake)
    filter_file(r"add_dependencies\(TestBar[^\)]*\)", "", test_cmake)
```

**典型报错：**
- `Cannot add target-level dependencies to non-existent target "TestFoo"`
- `target_link_libraries called with non-existent target`

### AutotoolsPackage 典型实现

```python
def configure_args(self):
    args = []
    args.extend(self.with_or_without("mpi"))
    args.append("--with-hdf5={0}".format(self.spec["hdf5"].prefix))
    return args
```

### MakefilePackage 典型实现

```python
parallel = False  # Fortran 模块依赖需串行

@property
def build_directory(self):
    """指定构建子目录（源码不在根目录时使用）"""
    return join_path(self.stage.source_path, "src")

def edit(self, spec, prefix):
    make_inc = join_path(self.stage.source_path, "make.inc")
    fcflags = "-O2"
    if spec.satisfies("%gcc@10:"):
        fcflags += " -fallow-argument-mismatch"
    filter_file(r"^FC=.*", "FC={0}".format(spack_fc), make_inc)
    filter_file(r"^FFLAGS=.*", "FFLAGS={0}".format(fcflags), make_inc)
    filter_file(r"^CC=.*", "CC={0}".format(spack_cc), make_inc)

@property
def build_targets(self):
    return ["all", "CC={0}".format(spack_cc)]

def install(self, spec, prefix):
    mkdirp(prefix.bin)
    install("program", prefix.bin)
```

### Generic Package 典型实现

```python
phases = ["configure", "build", "install"]

def configure(self, spec, prefix):
    pass

def build(self, spec, prefix):
    make()

def install(self, spec, prefix):
    make("install", "PREFIX={0}".format(prefix))
```

### Generic Package 自定义 phases

当软件的构建流程不适合任何标准基类时，使用 `phases` 属性自定义构建阶段：

```python
phases = ["build", "install"]

def build(self, spec, prefix):
    srcdir = self.stage.source_path
    os.environ["PWD"] = srcdir
    mkdirp(join_path(srcdir, "bin"))
    mkdirp(join_path(srcdir, "lib"))
    if spec.satisfies("@3:"):
        make("-C", srcdir, "suball.jemalloc")
    make("-C", srcdir, "suball1")
    make("-C", srcdir, "-j1", "all_libs")   # 强制串行
    make("-C", srcdir, "-j1", "all_progs")
    make("-C", srcdir, "suball2")
```

### Generic Package 两阶段构建（依赖 + 主体）

当软件使用捆绑依赖（如 COPASI 的 copasi-dependencies），需先构建所有依赖到本地前缀，再将主体指向该前缀：

```python
def _build_dependencies(self, spec, srcdir):
    dep_src = join_path(srcdir, "copasi-dependencies")
    dep_build = join_path(srcdir, "_dep_build")
    dep_install = join_path(srcdir, "_dep_install")
    mkdirp(dep_build)
    mkdirp(dep_install)

    build_type = spec.variants["build_type"].value
    cmake = which("cmake")
    with working_dir(dep_build):
        cmake(dep_src,
              "-G", "Unix Makefiles",
              "-DCMAKE_BUILD_TYPE={0}".format(build_type),
              "-DCMAKE_INSTALL_PREFIX={0}".format(dep_install),
              "-DBUILD_UI_DEPS=OFF",
              "-DGIT_SUBMODULE=OFF")
        make = which("make")
        make("-j{0}".format(make_jobs))
    return dep_install
```

### HPCKit 生态 configure + install（Generic Package）

**重要**：spack 没有内置 `cmake()` / `make()` 函数，必须用 `which()` 获取：

```python
def configure(self, spec, prefix):
    src = self.stage.source_path
    build_dir = join_path(src, "build")
    mkdirp(build_dir)

    # CC/CXX/FC 由 setup_build_environment 通过环境变量注入
    with working_dir(build_dir):
        cmake = which("cmake")
        cmake("..",
              "-DCMAKE_INSTALL_PREFIX={0}".format(prefix),
              "-DUSE_HDF5=ON",
              "-DUSE_BAM=ON")

def install(self, spec, prefix):
    build_dir = join_path(self.stage.source_path, "build")
    with working_dir(build_dir):
        make = which("make")
        make("-j{0}".format(make_jobs), "install")
```

**错误写法（spack 没内置 cmake/make 函数，会报 NameError）：**

```python
cmake("..", "-DCMAKE_INSTALL_PREFIX=...")
make("-j", "install")
```

### build + install 合并

如果构建步骤是 `make -j install`（一步到位），可省掉独立 `build` phase：

```python
phases = ["edit", "configure", "install"]

def install(self, spec, prefix):
    build_dir = join_path(self.stage.source_path, "build")
    with working_dir(build_dir):
        make = which("make")
        make("-j{0}".format(make_jobs), "install")
```

spack 在 `parallel = False` 时会把 `make_jobs` 设为 1，`make("-j{0}".format(make_jobs), ...)` 等价于 `make -j1 ...`，安全。

### Generic Package 手动调用 configure + make

当软件有 configure 脚本但不适合 AutotoolsPackage（如缺少标准 Autotools 结构），可在 `install()` 中手动调用：

```python
def install(self, spec, prefix):
    gnuconfig = spec["gnuconfig"]
    for conf in ["config.guess", "config.sub"]:
        src = join_path(gnuconfig.prefix, conf)
        dst = join_path("config", conf)
        if os.path.isfile(dst):
            os.chmod(dst, 0o755)
        shutil.copy2(src, dst)
        os.chmod(dst, 0o755)

    args = ["--prefix={0}".format(prefix)]
    if "+mpi" in spec:
        args.append("--enable-parallel")
        args.append("MPIF90=mpif90")
    configure = Executable("./configure")
    configure(*args)

    make("all")

    mkdirp(prefix.bin)
    for exe in find("bin", "*.x"):
        install(exe, prefix.bin)
```

### Generic Package 调用上游 build.py 脚本

当项目自带复杂构建脚本，需在正确的工作目录中通过 Spack 管理的 Python 调用：

```python
def build(self, spec, prefix):
    srcdir = self.stage.source_path
    python = spec["python"].command
    build_type = spec.variants["build_type"].value
    jobs = make_jobs

    build_args = [
        "build.py",
        "-j{0}".format(jobs),
        "--compiler", "gcc",
        "--type", build_type,
    ]

    with working_dir(join_path(srcdir, "source", "src", "python", "PyRosetta")):
        python(*build_args)
```

**关键点：**
- 使用 `spec["python"].command` 获取 Spack 管理的 Python 可执行文件
- 使用 `working_dir()` 确保 CWD 正确
- `make_jobs` 在构建阶段由 Spack 注入到模块命名空间中

### 清理残留的 CMake 缓存

当源码从下载缓存解压时，可能残留旧的 `CMakeCache.txt`，需在构建前清理：

```python
def _clean_stale_cmake_cache(self, srcdir):
    build_root = join_path(srcdir, "source", "build")
    if not os.path.isdir(build_root):
        return
    for dirpath, dirnames, filenames in os.walk(build_root):
        if "CMakeCache.txt" in filenames:
            os.remove(join_path(dirpath, "CMakeCache.txt"))
            cmake_files_dir = join_path(dirpath, "CMakeFiles")
            if os.path.isdir(cmake_files_dir):
                import shutil
                shutil.rmtree(cmake_files_dir)
```

### PythonPackage 典型实现

当软件有标准 `setup.py` 或 `pyproject.toml` 时：

```python
from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyTowhee(PythonPackage):
    """Towhee is a framework for creating embedding pipelines."""

    homepage = "https://towhee.io"
    pypi = "towhee/towhee-1.1.3.tar.gz"

    license("Apache-2.0")

    version("1.1.3", sha256="...")

    depends_on("python@3.7:", type=("build", "run"))
    depends_on("py-setuptools", type="build")
    depends_on("py-numpy", type=("build", "run"))
```

**注意：** PythonPackage 会自动处理 `pip install`，无需手动编写 install 方法。

### Python 脚本项目（无 setup.py）

当软件仅包含 Python 脚本文件，无标准构建系统，但有重量级 Python 依赖时：

```python
import os

from spack_repo.builtin.build_systems.generic import Package

from spack.package import *


class Proteinmpnn(Package):

    homepage = "https://github.com/dauparas/ProteinMPNN"
    git = "https://github.com/dauparas/ProteinMPNN.git"

    version("1.0.1", tag="v1.0.1", commit="905b0081...")

    depends_on("python@3.9:", type=("build", "run"))
    depends_on("py-pip", type="build")

    def install(self, spec, prefix):
        mkdirp(prefix.bin)
        mkdirp(prefix.lib)

        python = spec["python"].command
        python(
            "-m", "pip", "install",
            "--no-build-isolation",
            "--prefix={0}".format(prefix),
            "--no-cache-dir",
            "torch", "--index-url",
            "https://download.pytorch.org/whl/cpu",
        )

        install_tree(".", prefix.lib.proteinmpnn)

        python_ver = spec["python"].version.up_to(2)
        site_pkg = join_path(
            prefix.lib, "python{0}".format(python_ver), "site-packages",
        )
        wrapper = join_path(prefix.bin, "proteinmpnn")
        with open(wrapper, "w") as f:
            f.write("#!/bin/bash\n")
            f.write('export PYTHONPATH="{0}:${{PYTHONPATH}}"\n'.format(site_pkg))
            f.write('exec {0} {1} "$@"\n'.format(
                spec["python"].command.path,
                join_path(prefix.lib.proteinmpnn, "protein_mpnn_run.py"),
            ))
        os.chmod(wrapper, 0o755)
```

### Java/Ant 项目（Generic Package + Ant 构建）

```python
depends_on("java@1.6:", type=("build", "run"))
depends_on("ant", type="build")

def install(self, spec, prefix):
    filter_file(
        r'target="1\.6"\s+source="1\.6"',
        'target="1.8" source="1.8"',
        join_path(self.stage.source_path, "build.xml"),
    )

    ant = which("ant")
    ant("jar")

    dist_dir = join_path(self.stage.source_path, "dist")
    mkdirp(prefix.share.myapp)
    install_tree(dist_dir, prefix.share.myapp)

    mkdirp(prefix.bin)
    jars = find(join_path(prefix.share, "myapp"), "*.jar", recursive=False)
    wrapper = join_path(prefix.bin, "myapp")
    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\n")
        f.write('exec java -jar "{0}" "$@"\n'.format(jars[0]))
    os.chmod(wrapper, 0o755)
```

---

## 阶段八：环境注入

### setup_build_environment — 构建期环境（HPCKit 生态）

注入编译器运行时库、hmpi 库/头文件、MPI 编译器 wrapper：

```python
def setup_build_environment(self, env):
    spec = self.spec
    compiler_prefix = self._get_compiler_prefix()
    compiler_var = self._compiler_variant()

    # 编译器运行时库：gcc 与 bisheng 路径不同
    if compiler_var == "gcc":
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib64_public"))
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib64"))
    else:
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib"))

    # hmpi 的库与头文件
    hmpi = spec["hmpi"]
    if hmpi.libs:
        env.prepend_path("LD_LIBRARY_PATH", hmpi.libs.directories[0])
    if hmpi.headers:
        env.prepend_path("INCLUDE", hmpi.headers.directories[0])

    # MPI 编译器 wrapper（对应 export CC=mpicc CXX=mpicxx FC=mpifort）
    env.set("CC", hmpi.mpicc)
    env.set("CXX", hmpi.mpicxx)
    env.set("FC", hmpi.mpifc)
    env.set("F77", hmpi.mpif77)
```

### setup_build_environment — 通用环境注入

```python
def setup_build_environment(self, env):
    env.set("NETCDF", self.spec["netcdf-c"].prefix)
    env.set("HDF5", self.spec["hdf5"].prefix)
    env.prepend_path("LIBRARY_PATH", self.spec["zlib-api"].prefix.lib)
    env.prepend_path("C_INCLUDE_PATH", self.spec["zlib-api"].prefix.include)
    env.prepend_path("CPLUS_INCLUDE_PATH", self.spec["zlib-api"].prefix.include)
```

### setup_run_environment — 运行时环境（HPCKit 生态）

运行时环境要完整复刻构建时加载的 modulefile，让 `spack load` 后可执行文件能找到所有依赖：

```python
def setup_run_environment(self, env):
    spec = self.spec
    compiler_prefix = self._get_compiler_prefix()
    compiler_var = self._compiler_variant()

    # 编译器运行时库（对应 module load compiler）
    if compiler_var == "gcc":
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib64_public"))
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib64"))
    else:
        env.prepend_path("LD_LIBRARY_PATH",
                         join_path(compiler_prefix, "lib"))

    # hmpi 运行时（对应 module load hmpi）
    hmpi = spec["hmpi"]
    if hmpi.libs:
        env.prepend_path("LD_LIBRARY_PATH", hmpi.libs.directories[0])
    if hmpi.headers:
        env.prepend_path("INCLUDE", hmpi.headers.directories[0])

    # 主可执行文件
    env.prepend_path("PATH", self.prefix.bin)

    # hdf5-opt 运行时（对应 module load libs/hdf5-1.12.1）
    hdf5_prefix = spec["hdf5-opt"].prefix
    env.set("HDF5_PATH", hdf5_prefix)
    env.prepend_path("PATH", join_path(hdf5_prefix, "bin"))
    env.prepend_path("LD_LIBRARY_PATH", join_path(hdf5_prefix, "lib"))
    env.prepend_path("INCLUDE", join_path(hdf5_prefix, "include"))
```

### setup_run_environment — 通用模式

```python
def setup_run_environment(self, env):
    env.prepend_path("PATH", self.prefix.bin)
    env.prepend_path("LD_LIBRARY_PATH", self.prefix.bin)
    env.set("QDK_PATH", join_path(self.prefix, "QDK"))

    # Python 路径
    if self.spec.satisfies("+python"):
        env.prepend_path("PYTHONPATH", join_path(self.spec.prefix, "python"))
        env.set("TVM_LIBRARY_PATH", self.spec.prefix.lib)

    # Python site-packages 路径计算
    python_ver = self.spec["python"].version.up_to(2)
    site_packages = join_path(
        self.prefix.lib, "python{0}".format(python_ver), "site-packages",
    )
    env.prepend_path("PYTHONPATH", site_packages)
```

### 非标准库安装目录的运行时修复

有些项目把共享库安装到 `prefix/lib/<pkgname>` 等非标准子目录。解决方式是把真实库目录加入 `LD_LIBRARY_PATH`：

```python
def setup_run_environment(self, env):
    env.prepend_path("CMAKE_PREFIX_PATH", self.prefix)
    env.prepend_path("CMAKE_PREFIX_PATH", join_path(self.prefix, "lib", "chaste"))
    env.prepend_path("LD_LIBRARY_PATH", join_path(self.prefix, "lib", "chaste"))
```

**验证方法：**
```bash
spack load <package>
ldd $(spack location -i <package>)/lib/<pkgsubdir>/libfoo.so
```

### @run_after("install") 安装后钩子

当需要在标准 install 阶段后执行额外步骤（如安装 Python 绑定）时使用：

```python
@run_after("install")
def install_python(self):
    if not self.spec.satisfies("+python"):
        return
    prefix = self.spec.prefix
    source_dir = self.stage.source_path
    python_src = join_path(source_dir, "python")
    dest_python = join_path(prefix, "python")
    install_tree(python_src, dest_python)
    import glob
    for lib_file in glob.glob(join_path(str(prefix.lib), "libtvm*")):
        install(lib_file, join_path(dest_python, "tvm"))
```

### pip install 集成

```python
depends_on("py-pip", type="build")
depends_on("py-setuptools", type="build")
depends_on("py-wheel", type="build")

def install(self, spec, prefix):
    python = spec["python"].command
    python(
        "-m", "pip", "install",
        "--no-deps", "--no-build-isolation",
        "--prefix={0}".format(prefix),
        ".",
    )
```

**注意事项：**
- 使用 `--no-build-isolation` 确保使用 spack 管理的编译环境
- `--prefix={0}.format(prefix)` 将包安装到 spack 管理的前缀目录
- 安装后需在 `setup_run_environment` 中添加对应的 `python<ver>/site-packages` 到 PYTHONPATH
- 使用 `--no-deps` 时须确保所有依赖已就位；不使用时 pip 会自动拉取依赖

### Wrapper 脚本生成模式

对于没有标准入口点的项目，生成 shell wrapper 使其可通过命令行直接调用：

```python
def install(self, spec, prefix):
    python_ver = spec["python"].version.up_to(2)
    site_pkg = join_path(prefix.lib, "python{0}".format(python_ver), "site-packages")

    wrapper = join_path(prefix.bin, "mycommand")
    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\n")
        f.write('export PYTHONPATH="{0}:${{PYTHONPATH}}"\n'.format(site_pkg))
        f.write('exec {0} {1} "$@"\n'.format(
            spec["python"].command.path,
            join_path(prefix.lib, "mypkg", "main_script.py"),
        ))
    os.chmod(wrapper, 0o755)
```

**关键点：**
- 使用 `spec["python"].command.path` 获取绝对 Python 路径
- wrapper 中显式设置 PYTHONPATH（wrapper 可独立于 `spack load` 使用）
- 使用 `exec` 替换 shell 进程，信号处理更干净

### 安装辅助数据文件

```python
def install(self, spec, prefix):
    for subdir in ["docs", "crystals", "examples", "utilities"]:
        src = join_path(self.stage.source_path, subdir)
        if os.path.isdir(src):
            install_tree(src, join_path(prefix.share, subdir))

    qdk_root = join_path(prefix, "QDK")
    install_tree("shared", qdk_root)
    qdk_conf = join_path(qdk_root, "qdk.conf")
    filter_file(r"QDK_PATH_P=.*", "QDK_PATH_P={0}".format(prefix), qdk_conf)
```

---

## 阶段九：Patch 声明与应用

### patch 声明

sed 改源码的步骤沉淀为 patch 文件，在类级别声明（惯例：放在 `depends_on` 之后）：

```python
patch("CMakeLists.patch", when="@x.y.z", level=1)
patch("src_CMakeLists.patch", when="@x.y.z", level=1)
patch("Multinomial.patch", when="@x.y.z", level=1)
```

### level 判断规则

看 patch 文件里的路径前缀：

| patch 路径前缀 | level | patch 命令 |
|---------------|-------|-----------|
| `./CMakeLists.txt` | 1 | `patch -p1` |
| `a/src/CMakeLists.txt` | 1 | `patch -p1` |
| `CMakeLists.txt`（无前缀） | 0 | `patch -p0` |

### patch 应用顺序

spack 在 `edit` phase 之前按声明顺序自动应用所有 patch。`edit()` 里只需做 patch 表达不了的文件复制操作。

### patch 应用验证

```bash
cd /tmp && tar xzf pkg-x.y.z.tar.gz && cd pkg-x.y.z
patch -p1 < /path/to/patch1.patch
patch -p1 < /path/to/patch2.patch
```

### filter_file() 详解

`filter_file()` 是 Spack 提供的正则替换工具，适用于修改配置文件、Makefile、安装后的配置等：

```python
# 基本用法：正则匹配并替换
filter_file(r"^FC=.*", "FC={0}".format(spack_fc), make_inc)

# 安装后修补配置文件中的路径
filter_file(r"QDK_PATH_P=.*", "QDK_PATH_P={0}".format(prefix), qdk_conf)

# 修补 configure 脚本添加架构支持
filter_file(
    r"powerpc64-\*-linux-gnu \)\s*arch=ppc64\s*;;",
    "powerpc64-*-linux-gnu )   arch=ppc64   ;;\n"
    "\t\taarch64-*-linux-gnu )   arch=x86_64 ;;",
    "configure",
)
```

**注意：** `filter_file` 是逐行匹配的 `re.sub`，不支持跨行 `\n` 匹配。如果需要删除连续的两行，必须分两次调用。

### HPCKit 常见 CMake 改造 patch 模式

**注入 OpenMP：**

```diff
--- CMakeLists.txt
+++ CMakeLists.txt
@@ -23,6 +23,7 @@
     set(CMAKE_BUILD_TYPE "Release")
 endif()
 
+add_compile_options(-fopenmp)
 if(${CMAKE_VERSION} VERSION_LESS 3.1)
```

**给 vendor configure 加 aarch64 build/host：**

```diff
--- CMakeLists.txt
+++ CMakeLists.txt
@@ -48,7 +48,7 @@
     CONFIGURE_COMMAND autoheader && autoconf && .../configure 
-        --prefix=${PREFIX} --disable-bz2 --disable-lzma --disable-libcurl
+        --prefix=${PREFIX} --disable-bz2 --disable-lzma --disable-libcurl --build=aarch64-unknown-linux-gnu --host=aarch64-unknown-linux-gnu CPPFLAGS=-foverflow-shift-alt-behavior
```

**给 src/CMakeLists.txt 注入 MPI find_package：**

```diff
--- src/CMakeLists.txt
+++ src/CMakeLists.txt
@@ -30,6 +30,7 @@
 if(USE_HDF5)
     find_package( HDF5 REQUIRED )
+    find_package( MPI REQUIRED )
 endif(USE_HDF5)
@@ -44,6 +45,7 @@
     if(HDF5_FOUND)
         include_directories( ${HDF5_INCLUDE_DIRS} )
+        include_directories( ${MPI_CXX_HEADER_DIR} )
@@ -61,5 +63,6 @@
+ target_link_libraries(kallisto "-fopenmp")
```

### edit phase 中替换 config.guess/config.sub

vendor 子项目（htslib、FoX 等）内置的 `config.guess` / `config.sub` 版本太老，在 aarch64 上识别不出平台三元组，需用 spack 的 `gnuconfig` 替换：

```python
def edit(self, spec, prefix):
    src = self.stage.source_path
    gnuconfig = spec["gnuconfig"].prefix
    target_dir = join_path(src, "ext", "htslib")
    for conf in ("config.guess", "config.sub"):
        dst = join_path(target_dir, conf)
        if os.path.isfile(dst):
            os.chmod(dst, 0o755)
        shutil.copy2(join_path(gnuconfig, conf), dst)
        os.chmod(dst, 0o755)
```

---

## 阶段十：处理常见构建问题

### Fortran 模块并行编译

Fortran 的 `USE module` 依赖 `.mod` 文件，并行 make 可能因竞争失败：

```python
parallel = False
```

**parallel = False 适用场景：**
- vendor 子库（htslib）要先 `make lib-static` 出来再被主项目链接
- Fortran `.mod` 模块依赖链
- 子项目间存在构建顺序依赖

### 编译器版本适配

```python
if spec.satisfies("%gcc@10:"):
    fcflags += " -fallow-argument-mismatch"
```

### C 预处理器 traditional 模式的 `#if !defined()` 陷阱

Fortran 项目通常使用 `/usr/bin/cpp -P -traditional` 做预处理。在此模式下，`# if !defined (METIS_5)` 这类写法可能不被正确解析。

**解决方式：** 在 `patch()` 或 `edit()` 中替换为 `#ifndef`：

```python
filter_file(
    r"^#\s*if\s*!defined\s*\(METIS_5\)",
    "#ifndef METIS_5",
    join_path(srcdir, "mod_par.F"),
)
```

**典型信号：** 构建日志的预处理命令中已包含 `-DMETIS_5`，但链接时仍报 `undefined reference to 'partition_'`。

### 内置古老 setuptools 引导（ez_setup）的修补

```python
setup_py = join_path(pkg_dir, "setup.py")
filter_file(r"^import ez_setup.*$", "", setup_py)
filter_file(r"^ez_setup\.use_setuptools.*$", "", setup_py)
```

### MPI 编译器包装器

```python
# 正确做法：从 spec 获取完整路径
fc = spec["mpi"].mpifc
cc = spec["mpi"].mpicc

# 错误做法：依赖 PATH 中的 mpif90
fc = "mpif90"  # 可能指向错误的 MPI 实现
```

### HPCKit 中使用 hmpi 编译器 wrapper

在 HPCKit 生态下，通过 `setup_build_environment` 设置 MPI wrapper 而非硬编码：

```python
# 对应 export CC=mpicc CXX=mpicxx FC=mpifort
env.set("CC", hmpi.mpicc)
env.set("CXX", hmpi.mpicxx)
env.set("FC", hmpi.mpifc)
env.set("F77", hmpi.mpif77)
```

### ⚠ hmpi 缺少 OMPI_CC 注入（已知缺陷，影响链接正确性）

**这是消费者包链接 hmpi 时最隐蔽的陷阱。** hmpi 的 `setup_dependent_build_environment` 只设置了 `OPAL_PREFIX`，**没有设置 `OMPI_CC`/`OMPI_CXX`/`OMPI_FC`/`OMPI_F77`**。标准 openmpi 的 spack package.py 会设置这些变量（见 builtin `openmpi/package.py` 的 `setup_dependent_build_environment`），让 mpicc (opal_wrapper) 改用 spack 编译器 wrapper（`spack_cc`）而非 wrapper-data.txt 中写死的裸 `gcc`/`clang`。

**后果（实测验证）：**
- mpicc 调用系统 PATH 中的裸 gcc，而非 spack 管理的编译器
- 编译器版本可能与 hmpi 库编译时用的版本不匹配（实测：系统 gcc 10.3.1 vs hpckit gcc 12.3.1 vs `libmpi.so` 内嵌 `GCC: 12.3.1`）
- spack 的 rpath 注入丢失
- 编译器运行时库路径（gcc-runtime/lib 等）丢失

**诊断方法（一条命令）：**
```bash
# 在 spack 构建环境中检查 mpicc --show 的编译器
spack build-env <pkg> %gcc -- bash -c 'mpicc --show | awk "{print \$1}"'
# 输出裸 "gcc" → OMPI_CC 未注入（有问题）
# 输出 spack wrapper 路径 → OMPI_CC 已注入（正确）
```

**对比验证 — hmpi 库编译器版本：**
```bash
# 从 hmpi 的 libmpi.so 提取编译器版本
strings <hmpi_prefix>/lib/libmpi.so | grep -oE "GCC:.*" | head -1
```

**strace 追踪法（定位 opal_wrapper 读哪个 wrapper-data.txt）：**
```bash
strace -f -e trace=openat <hmpi_prefix>/bin/mpicc --show 2>&1 | grep wrapper-data
# 如果读 /usr/lib64/openmpi/... → 指向系统 openmpi（错误）
# 如果读 <hmpi_prefix>/share/openmpi/... → 指向 hmpi（正确）
```

**修复方向：** 需修改 hmpi 的 package.py，在 `setup_dependent_build_environment` 末尾添加（复刻标准 openmpi 的做法）：

```python
dependent_module = dependent_spec.package.module
for var_name, attr_name in (
    ("OMPI_CC", "spack_cc"),
    ("OMPI_CXX", "spack_cxx"),
    ("OMPI_FC", "spack_fc"),
    ("OMPI_F77", "spack_f77"),
):
    if hasattr(dependent_module, attr_name):
        env.set(var_name, getattr(dependent_module, attr_name))
```

详见 `references/hmpi-ompi-cc-debugging.md`（含完整 A/B 对照实验复现步骤）。

### ⚠ spack compiler-wrapper 静默禁用 SVE 自动向量化（鲲鹏920 + HPCKit GCC）

spack 的 compiler-wrapper（`compiler-wrapper-1.1.0`）会传递 `-mcpu=native` 到 CFLAGS（config.log 和 Makefile 中可见），但实际编译出的 .o 文件 **0 个 SVE 指令**。直接用同一 HPCKit gcc 12.3.1 二进制 + 同一 CFLAGS 编译同一源文件，却有 8+ 个 SVE 指令（`whilelo`、`ld1w z`、`fadda`）。

**诊断方法（A/B 对照）：**
```bash
# 1. 检查 spack 编译的 .o 是否有 SVE 指令
objdump -d euclidean_dist.o | grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z"
# → 0（问题）

# 2. 直接用 HPCKit gcc 编译同一文件
GCC12="<hpckit_prefix>/HPCKit/25.1.0/compiler/gcc/bin/gcc"
$GCC12 -O3 -mcpu=native -ffp-contract=off -I<src> -include config.h -S -o /tmp/test.s euclidean_dist.c
grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z" /tmp/test.s
# → 8+（正常）
```

**修复方式：** 在 `setup_build_environment` 中直接设 `CC`/`CXX` 为 HPCKit gcc 的绝对路径，绕过 spack wrapper：

```python
def setup_build_environment(self, env):
    gcc_dir = join_path(
        self.spec["hpckit"].prefix,
        "HPCKit", "25.1.0", "compiler", "gcc", "bin",
    )
    env.set("CC", join_path(gcc_dir, "gcc"))
    env.set("CXX", join_path(gcc_dir, "g++"))
    env.set("CFLAGS", "-O3 -mcpu=native ...")
```

**验证修复生效：**
```bash
objdump -d $(which kalign) | grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z"
# → 100+（修复后）
```

### ⚠ -flto 禁用 GCC SVE 自动向量化

`-flto`（Link-Time Optimization）会禁用 GCC 12.3.1 的 SVE 自动向量化。这是一个反直觉的交互：LTO 本应跨模块优化，但实际导致 SVE 指令完全消失。

**验证（控制变量 A/B）：**
```bash
GCC12="<hpckit_prefix>/HPCKit/25.1.0/compiler/gcc/bin/gcc"
echo 'float dot(float* a, float* b, int n){float s=0;for(int i=0;i<n;i++)s+=a[i]*b[i];return s;}' > /tmp/dot.c

# 无 -flto
$GCC12 -O3 -mcpu=native -S -o /tmp/dot_nolto.s /tmp/dot.c
grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z" /tmp/dot_nolto.s  # → 5

# 有 -flto
$GCC12 -O3 -mcpu=native -flto -S -o /tmp/dot_lto.s /tmp/dot.c
grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z" /tmp/dot_lto.s     # → 0
```

**结论：** 鲲鹏920 上需要 SVE 自动向量化时，**不要加 `-flto`**。在 package.py 的 CFLAGS 中省略它。

### ⚠ -ffast-math 破坏 k-means 等精确浮点收敛循环

`-ffast-math`（GCC 和 BiSheng clang 均如此）会破坏依赖精确浮点 `!=` 比较判断收敛的循环（如 kalign 的 `bisectingKmeans.c` 中 `if(wl[j] != cl[j])`）。FMA 融合和运算重排使浮点除法结果每次迭代产生微小差异，导致收敛循环永远无法达到精确相等 → 跑满 10000 次迭代 → `ERROR_MSG("Failed.")` → 程序挂起或崩溃。

**三种 FP 模式对比（kalign bisectingKmeans 收敛测试）：**

| CFLAGS | FMA | IEEE 比较 | 收敛 | 性能 |
|--------|-----|-----------|------|------|
| 默认（不设 -ffast-math 也不设 -ffp-contract=off） | ✅ | ✅ | ✅ 正常 | 最优 |
| `-ffast-math` | ✅ | ❌ | ❌ 挂起/失败 | — |
| `-ffp-contract=off` | ❌ | ✅ | ✅ 正常 | 慢（禁 FMA 降速） |

**修复方案（优先级排序）：**

1. **最佳方案**：不设 `-ffast-math`，不设 `-ffp-contract=off`。GCC 默认允许 FMA 同时保持 IEEE 比较语义 → 性能最优 + 无收敛问题。
2. **安全网 patch**：在 `edit()` 中将精确 `!=` 改为容差比较 `fabsf(a - b) > 1e-6f`，并降低最大迭代次数阈值 + 添加 fallback（50/50 split）。
3. **如果必须用 `-ffast-math`**：则必须同时应用容差 patch，且需要验证所有浮点比较路径。

**容差 patch 模板（以 kalign bisectingKmeans.c 为例）：**
```python
@run_before("autoreconf")
def edit(self):
    bkm = join_path(self.stage.source_path, "src", "bisectingKmeans.c")
    # 精确 != → 容差比较
    filter_file(r"if\(wl\[j\] != cl\[j\]\)\{",
                "if(fabsf(wl[j] - cl[j]) > 1e-6f){", bkm)
    filter_file(r"if\(wr\[j\] != cr\[j\]\)\{",
                "if(fabsf(wr[j] - cr[j]) > 1e-6f){", bkm)
    # 降低阈值 + fallback
    filter_file(r"if\(stop == 10000\)\{", "if(stop == 200){", bkm)
    filter_file(r'ERROR_MSG\("Failed\."\);',
                "num_l = 0; num_r = 0; "
                "for(i = 0; i < num_samples/2;i++){ sl[num_l] = samples[i]; num_l++; } "
                "for(i = num_samples/2; i < num_samples;i++){ sr[num_r] = samples[i]; num_r++; } "
                "break;", bkm)
```

### ⚠ KML 库 stdout 警告污染 meson run_command（影响所有 meson-python 构建）

KML 的 `libkblas.so` 初始化时向 **stdout**（非 stderr）打印 `Warning: libsdma_dk.so ... not found` 警告。在 meson 构建系统中，`run_command(py3, ['-c', 'import numpy; ...'])` 的 stdout 会被此警告污染，导致路径/版本字符串包含警告文本，`include_directories()` 和版本检查失败。

**受影响场景：** scipy 的 numpy include 路径检测、pythran include 路径检测、`f2py -v` 版本检查。所有 `import numpy` 的 run_command 均受影响。

**诊断：** 检查 `build/meson-logs/meson-log.txt` 中 `run_command` 的 stdout 是否包含 `Warning: libsdma` 文本。

**修复方案（多管齐下）：**
1. **通过 meson native file 提供 external property**（适用于 include 路径）：在 `config_settings()` 中写 native file `[properties]` 提供 `numpy-include-dir` / `pythran-include-dir`，meson 跳过 `run_command`。
2. **patch meson.build** 过滤 `f2py -v` 等无法绕过的 run_command 输出中的 `Warning:` 行。
3. **py-numpy 的 `setup_run_environment` 注入 KML 库路径**（解决 runtime `import numpy` 失败，但不解决 stdout 污染——两者独立）。

详见 `references/kml-stdout-warning-pollution.md`（含诊断命令、KML 环境变量无效实测、native file 写法、KML 库路径速查）。

### CMake + MPI 项目的编译器传递

**重要：** 不要将 MPI wrapper 直接传给 `CMAKE_Fortran_COMPILER`。正确做法是分离编译器和 MPI：

```python
cmake_args = [
    cmake_src,
    "-DCMAKE_C_COMPILER={0}".format(self.compiler.cc),
    "-DCMAKE_CXX_COMPILER={0}".format(self.compiler.cxx),
    "-DCMAKE_Fortran_COMPILER={0}".format(self.compiler.fc),
    "-DMPI_C_COMPILER={0}".format(spec["mpi"].mpicc),
    "-DMPI_CXX_COMPILER={0}".format(spec["mpi"].mpicxx),
    "-DMPI_Fortran_COMPILER={0}".format(spec["mpi"].mpifc),
]
```

### CMake 源码在子目录

当 CMakeLists.txt 不在仓库根目录时，需指定源码路径：

```python
def build(self, spec, prefix):
    srcdir = self.stage.source_path
    cmake_src = join_path(srcdir, "Nwpw")  # CMakeLists.txt 所在子目录
    build_dir = join_path(srcdir, "_build")
    mkdirp(build_dir)

    cmake = which("cmake")
    with working_dir(build_dir):
        cmake(cmake_src, "-DCMAKE_INSTALL_PREFIX={0}".format(prefix), ...)
        make = which("make")
        make("-j{0}".format(make_jobs))
```

### 架构适配（x86 vs aarch64 / 鲲鹏）

```python
# 避免硬编码 x86 特定标志
fcflags = "-fPIC -O2 -fdefault-real-8"  # 通用
# 不要用：-march=native -mavx（x86 专用）
```

当上游 CMakeLists.txt 硬编码 x86 标志时，使用 `patch()` 在构建前移除：

```python
def patch(self):
    import re

    cmakelists = join_path(self.stage.source_path, "Nwpw", "CMakeLists.txt")
    with open(cmakelists, "r") as fh:
        content = fh.read()

    # 修正 arm64/aarch64 架构检测
    content = content.replace(
        '${CMAKE_SYSTEM_PROCESSOR} STREQUAL "arm64"',
        '${CMAKE_SYSTEM_PROCESSOR} MATCHES "arm64|aarch64"',
    )
    # 移除 x86 专用标志
    content = re.sub(r"-m64\s*", "", content)
    content = re.sub(r"-mfpmath=sse\s*", "", content)
    content = re.sub(r"-mtune=native\s*", "", content)

    with open(cmakelists, "w") as fh:
        fh.write(content)
```

**常见需要移除的 x86 标志：** `-m64`、`-m32`、`-msse*`、`-mavx*`、`-mfpmath=sse`、`-march=native`、`-mtune=native`

---

## 包名命名规则

**spack 仓库子目录名用下划线 `_`，spec 字符串与 `depends_on()` / `spec["..."]` 用连字符 `-`**：

| 位置 | 写法 | 示例 |
|------|------|------|
| 仓库子目录名 | 下划线 `_` | `packages/ncbi_blast_opt/` |
| Python 类名 | 驼峰（无连字符） | `class NcbiBlastOpt(Package)` |
| spec 字符串 | 连字符 `-` | `spack install ncbi-blast-opt` |
| `depends_on(...)` | 连字符 `-` | `depends_on("ncbi-blast-opt")` |
| `spec["..."]` 索引 | 连字符 `-` | `spec["ncbi-blast-opt"]` |

### 验证方式

```bash
spack list | grep <pkg-name>            # 显示用 -
spack spec <pkg-name> %llvm             # spec 用 -
```

`spack list` 输出会把目录名 `_` 自动转成 `-` 显示。例如目录 `psipred_opt` 在 `spack list` 里显示为 `psipred-opt`。

### 类名注意

Python 类名用驼峰，**不能**包含连字符（Python 标识符不允许）。目录 `ncbi_blast_opt` 对应类名 `NcbiBlastOpt`。

### spec 解析的歧义

`spec "pkg-ver"`（如 `hpckit-26.0.RC1`）会被解析为版本约束，不是包名。包名带 `-` 后跟版本号时需用 `@` 显式声明：

```python
# 错：会被解析成 name=RC1
spec["hpckit-26.0.RC1"]

# 对：用 @ 显式声明版本
"hpckit@26.0.RC1"
```

但纯包名（如 `ncbi-blast-opt`、`hdf5-opt`）后跟非版本字符串，能被正确解析为包名。

---

## 阶段十一：本地仓库注册与验证

### 仓库目录结构

```
my_repo/
├── repo.yaml              # namespace 声明
└── packages/
    └── my_package/
        └── package.py     # 包定义
```

### repo.yaml 格式

```yaml
repo:
  namespace: 'my_repo_name'
  api: v2.4
```

### 注册仓库

```bash
spack repo add /path/to/my_repo
spack repo list  # 确认已注册
```

### 语法验证

```bash
python -c "import ast; ast.parse(open('package.py').read()); print('AST OK')"
```

### spack import checks

```bash
spack style -t import path/to/package.py
```

`black` / `flake8` / `isort` 等工具如果环境没装，会报 `'NoneType' object is not callable`，这是工具不存在的问题，不是 package.py 的问题。只看 `import checks` 结果即可。

### 依赖树检查

```bash
spack spec <package>@<ver>%<compiler>  # 查看完整依赖解析
spack info <package>  # 确认 Spack 识别包
```

### 安装

```bash
spack install <package>@<ver>%<compiler> ^<mpi_preference>
# HPCKit 生态示例：
spack install pkg-opt %bisheng
```

### 运行验证

```bash
spack load <package>
which <binary>
<binary> --version
file $(which <binary>)  # 确认 ELF 架构（aarch64 vs x86_64）
```

### 卸载与重装

```bash
spack uninstall <package>
spack clean -s <package>   # 清理构建缓存
spack install <package>    # 重新安装
```

---

## 实战案例索引

| 软件 | 构建系统 | 基类 | 关键特点 |
|------|---------|------|---------|
| **kallisto-opt** | **CMake + vendor htslib** | **Package (Generic)** | **HPCKit 双变体 bisheng/gcc、hmpi 环境注入、gnuconfig 替换、aarch64 patch、MPI find_package 注入** |
| WRF | 交互式 configure | Package (Generic) | 需解析交互式问答、csh 脚本 |
| LAMMPS | CMake | CMakePackage | 大量 variants（50+）、多 GPU 后端 |
| GROMACS | CMake | CMakePackage | CUDA/SYCL 加速支持 |
| Meep | Autotools | AutotoolsPackage | 标准 configure_args 模式 |
| Chaste | CMake | CMakePackage | 旧版 Boost API 兼容修补、缺失 FFTW 发现逻辑需手动注入 include 路径、禁用测试后残留 target 需 patch() 移除、库安装在 `lib/chaste` 需修正 `LD_LIBRARY_PATH` |
| HYCOM | 原生 Makefile | MakefilePackage | 动态生成 config 文件、串行编译、多选型 variant |
| Palabos | CMake（无 install 规则） | CMakePackage | patch() 移除 examples 子目录、自定义 install 安装静态库+头文件 |
| VASPKIT | Makefile + make.inc | MakefilePackage | build_directory 属性、filter_file 修改 make.inc、辅助数据安装 |
| SWMM | CMake | CMakePackage | CMAKE_DISABLE_FIND_PACKAGE 禁用可选依赖、setup_run_environment |
| QDK | Makefile | MakefilePackage | 非标准目录布局安装、安装后 filter_file 修补配置文件、自定义环境变量 |
| TVM | CMake + Python 绑定 | CMakePackage | submodules=True、@run_after 安装 Python 绑定、大量 Python 依赖链 |
| WanT | configure + make（非标准） | Package (Generic) | gnuconfig 替换、手动 Executable("./configure")、架构 filter_file 修补 |
| Cactus | 多阶段 make | Package (Generic) | 自定义 phases、版本条件构建、pip install 集成、复杂 setup_run_environment |
| ProteinMPNN | Python 脚本（无 setup.py） | Package (Generic) | pip install PyTorch 预编译轮子、install_tree 安装源码+模型权重、wrapper 脚本、PYTHONPATH 管理 |
| ProtTest | Java/Ant | Package (Generic) | Ant 构建 JAR、Java source/target 版本修补（1.6→1.8）、wrapper 脚本 |
| py-towhee | Python (pyproject.toml) | PythonPackage | 标准 PythonPackage 流程、pypi 源指定 |
| ParaFEM | Makefile | Package (Generic) | 非标准 Makefile 手动调用 make |
| FVCOM | 原生 Makefile | MakefilePackage | MPI 并行海洋模型、Fortran 编译、`cpp -traditional` 对 `#if !defined` 不兼容需改 `#ifndef` |
| PyRosetta | 自定义 build.py + CMake/Ninja | Package (Generic) | 调用上游 build.py 脚本、CMake 缓存清理、get_full_repo=True、ez_setup 修补 |
| COPASI | CMake + 捆绑依赖 | Package (Generic) | resource() 获取依赖仓库、两阶段构建（先依赖后主体） |
| PWDFT | CMake（子目录 + MPI） | Package (Generic) | CMake 源码在子目录、patch() 移除 x86 标志、CMake+MPI 编译器分离传递 |
| **Elmerfem** | **CMake** | **CMakePackage** | **路径A2 修改：GCC 12+ DO 循环变量 `filter_file` 修复、Flang .mod 不兼容须 `^netcdf-fortran %llvm`、FindMKL.cmake Flang FATAL_ERROR 须显式 BLAS_LIBRARIES、Clang 19+ implicit-function-declaration 降级** |

---

## 关键规则速查

| 规则 | 说明 |
|------|------|
| spack 没内置 `cmake()`/`make()` | 必须用 `which("cmake")` / `which("make")` |
| 包名含 `-` 的 `libs`/`headers` 会失败 | 用 `spec["pkg-opt"].prefix` 拼路径 |
| sed 改源码优先用 patch 文件 | 比 Python 行内字符串操作清晰，可独立审查；惯例放在 `depends_on` 之后 |
| patch level 看路径前缀 | `./` 或 `a/` → `level=1`；无前缀 → `level=0` |
| HPCKit 双变体 | `when="%llvm"` bisheng / `when="%gcc"` gcc，运行时库路径不同 |
| HPCKit 计算库（kpblas/kpfft/kpkml/hmpi 等）依赖 | 用 `depends_on("xxx compiler_variant=bisheng", when="%llvm")` + `depends_on("xxx compiler_variant=gcc", when="%gcc")`，**不写版本**，让用户通过 `^hpckit@<ver>` 指定 |
| kpkml 是聚合包,按需选用 | 会拉入所有 KML 子组件,只在确实需要全套 KML 时使用;只需单个库时直接 depends_on 对应包 |
| 不要修改 kp*/hmpi 包本身 | 它们是基础设施数学库的封装，新 package.py 只作为消费者 |
| `compiler_variant` 是 kp* 内部 variant | 不应让用户手动指定，由 `%llvm`/`%gcc` 自动映射 |
| **仓库子目录名用下划线 `_`** | spack 仓库目录与类名必须用 `_`（如 `psipred_opt` / `PsipredOpt`）；spec 字符串用 `-`（如 `psipred-opt`） |
| `module load` → `depends_on` | 每条 module load 对应一个 depends_on |
| `export CC=mpicc` → `env.set("CC", hmpi.mpicc)` | 用 hmpi wrapper 路径，不用裸字符串 |
| `cp config.guess` → `edit()` + `depends_on("gnuconfig")` | vendor 子项目的 autotools 适配 |
| `parallel = False` | vendor 子库先编出来再被链接，或 Fortran 模块依赖 |
| `setup_run_environment` 要复刻运行时 modulefile | 编译器 + hmpi + hdf5 都要注入 |
| 不改 yaml 配置 | 所有问题只在 package.py 里解决 |
| CMake 项目必须声明 `depends_on("c")` | 即使纯 C++ 项目，否则报 `SPACK_CC_* variables not set` |
| MPI wrapper 不传给 `CMAKE_*_COMPILER` | 用 `MPI_*_COMPILER` 提示 `find_package(MPI)` |
| aarch64 需移除 x86 标志 | `-m64`、`-msse*`、`-mavx*`、`-march=native` 等 |
| `filter_file` 不支持跨行匹配 | 删连续两行需分两次调用 |
| **hmpi 缺少 OMPI_CC 注入** | hmpi 的 `setup_dependent_build_environment` 未设 `OMPI_CC`/`OMPI_CXX`/`OMPI_FC`/`OMPI_F77`，导致 mpicc 用裸 gcc 而非 spack wrapper → 编译器版本不匹配 + rpath 丢失。诊断：`spack build-env <pkg> %gcc -- bash -c 'mpicc --show \| awk "{print \$1}"'`，输出裸 `gcc` 即有问题。修复：复刻 openmpi 的 `OMPI_CC=spack_cc` 注入。详见 `references/hmpi-ompi-cc-debugging.md` |
| **spack compiler-wrapper 禁用 SVE** | wrapper 传递 `-mcpu=native` 但编译出 0 SVE 指令；需在 `setup_build_environment` 直接设 `CC` 为 HPCKit gcc 绝对路径绕过 |
| **-flto 禁用 GCC SVE 向量化** | `-flto` 导致 SVE 指令消失（0条）；鲲鹏920 SVE 优化时不要加 `-flto` |
| **-ffast-math 破坏浮点收敛循环** | 精确 `float !=` 比较在 `-ffast-math` 下永不收敛→挂起；GCC 默认 FP 语义（不设 -ffast-math 也不设 -ffp-contract=off）最优 |
| **libgomp(GCC) vs libomp(BiSheng)** | OpenMP task 密集型应用中 libomp 调度开销占 60%+，libgomp 几乎零开销；优先用 GCC 编译 |
| **KML 变体按固定向量长度编译** | `kml/<variant>/lib/{neon,sve,sve512,sve_no_f64mm,sme(=matrix)}` 是同一 ABI 按不同 ISA/VL 各编一份，选型只换 `LD_LIBRARY_PATH`；VL 不匹配会**静默算错**（0xd22 的 `matrix`/`sme` KBLAS 假定 SME VL=512bit，内核默认 256bit，须**每线程** `prctl(PR_SME_SET_VL,64)`；`sve/` 版库在 512bit 机器上相反需设 256bit）。目录选路规则照抄 `kml/<variant>/env/setvars.sh`；详见 `references/kml-isa-variants.md` |
| **packages.yaml 多值变体 require 语法** | `compiler_variant` 是多值变体（非布尔），`require` 中写 `"compiler_variant=gcc"` 而非 `"+compiler_variant=gcc"`（`+` 仅用于布尔变体）。详见 `references/packages-yaml-config-gotchas.md` |
| **all.compiler 已废弃** | Spack v1.0+ 忽略 `packages:all:compiler`，不要在 packages.yaml 中设置全局编译器偏好；用 `%gcc`/`%llvm` spec 约束 |
| **不要在 packages.yaml 强制 hpckit 版本** | `hpckit: require: "@26.1.RC1"` 会与 kpkml 子包版本依赖链冲突（kpkml 只有 26.0.RC1/25.1.0，子包有 26.1.RC1）。省略版本约束让 concretizer 自行匹配 |
| **hpckit 双 repo namespace 冲突** | hpckit 同时存在于 builtin 和 kunpeng920prof repo，可能导致 `cannot come from both namespaces`。repos.yaml 中 kunpeng920prof 放 builtin 之上，移除 hpckit 版本约束可缓解 |
| **通用名 ≠ spack 包名** | 用户写 `elmer`，spack 中实际包名为 `elmerfem`。用 `spack list "elmer*"` 模糊搜索找到正确名 |
| **LAMMPS 版本号格式不匹配** | 官方 `2Aug2023` → spack `20230802.4`（`YYYYMMDD.N`）。用 `spack info lammps \| grep -A 30 "Safe versions:"` 查正确版本号 |
| **CSV 风格 .yaml 无法用 write_file 写入** | `packages_to_install.yaml` 含 CSV 行（`pkg,ver,compiler`），write_file/patch 的 YAML 校验会拒绝。用 `terminal` + `cat << 'EOF'` 绕过 |
| **builtin 包版本滞后上游** | `spack info <pkg>` 成功 ≠ 指定版本可解析。`spack spec pkg@<新版> %gcc` 报 `No version exists` 时先查包内 Safe versions 最高版本 + web_search 确认上游是否已发布（实测 namd@3.0.3：builtin 仅 3.0.1，上游 2026-07 已发 3.0.3）。处理：降级到 builtin 最近版本（改清单须用户确认）或交下一阶段写 package.py/手动编译。详见 `references/spack-package-verification-gotchas.md` 陷阱 6 |
| **manual_download 包需预置 tarball** | license 限制包（如 namd 声明 `manual_download=True`，URL 为 `file://{os.getcwd()}/NAMD_*.tar.gz`）会在**安装发起 CWD** 找 tarball。清单含此类包时，验证阶段先确认 tarball 已在盘上（`find ... -iname 'NAMD_*Source*'`），不在则把"官网手动下载 + 放入安装脚本 CWD"写进交接报告，否则安装必败于获取源码。详见 `references/spack-package-verification-gotchas.md` 陷阱 7 |
| **验证阶段可代改的文件边界** | workflow 清单 `packages_to_install.yaml` 是用户手填的，未经确认不得代改（删条目、降版本都算）；询问超时未响应时保守保留原条目，把问题+处理路径写进验证报告交接。自述"由本阶段执行生成"的报告 .md 可整体重写；`AI_INSTRUCTION.md`/`DESCRIPTION.md` 等固定指令文件执行前后必须一致（mtime 核验） |
| **BiSheng 在 spack 中注册为 `llvm`** | `spack install pkg %bisheng` 报错 `cannot depend on bisheng`。BiSheng 以 clang/flang 二进制注册在 `llvm` 外部包中，用 `%llvm` 指定。验证：`spack compiler list` 显示 `llvm@<ver>`，prefix 指向 HPCKit bisheng 目录。**批量安装脚本与 bisheng 映射须实测**：旧版脚本硬拼 `%bisheng` 在 spec 校验即败（重试逻辑仍拼同串，救不回）；2026-09-28 实测 workflow `stage3-install/install_batch.sh` 已内置 bisheng→llvm 映射（第 161/184/357 行），`both`/`bisheng` 条目可直接展开，无需清单侧规避。拿到新脚本先 `grep -n bisheng install_batch.sh` 确认有无映射，勿沿用历史结论。脚本侧应加 bisheng→llvm 映射，或清单只填 gcc。详见 `references/spack-package-verification-gotchas.md` |
| **local_repo 简化包遮蔽 builtin** | local_repo 中与 builtin 同名的简化包（如 openblas 只有 `build_system` variant，缺 `threads`）会遮蔽 builtin。cp2k 有 `depends_on("openblas threads=openmp")`，评估时因缺 variant 报错 → 所有依赖 blas 的包全挂。修复：移除/重命名 local_repo 中的同名包。`buildable: false` 不够（concretizer 仍验证 variant） |
| **spack provider 列表跨 scope 合并** | `packages:all:providers:blas` 在各 scope 中是追加合并，不是替换。系统级 `[kpkml]` + 默认 `[openblas]` = `[kpkml, openblas]`。`spack config blame packages` 可查看各 scope 贡献 |
| **spack 1.2.1 仓库结构** | 需 `spack_repo/<namespace>/{repo.yaml,packages/}` 子目录，repo.yaml 放 namespace 目录内。`spack repo add` 可能失败，用 `spack config add "repos:<ns>:<path>"` 更可靠 |
| **cp2k conflicts("%clang")** | cp2k package.py 明确声明不支持 clang/BiSheng，`spack install cp2k %llvm` 报 `conflicts with '%clang'`。上游限制无法绕过，清单标 `both` 的 cp2k 只能装 gcc |
| **openblas 测试失败中断安装** | openblas@0.3.30+ 在 aarch64 上 `make all` 跑 LAPACK 测试 SIGABRT (Error 134)。修复：复制 package.py 到本地 repo，将 `build_targets` 从 `["all"]` 改为 `["shared"]`（`shared` 依赖 `libs`+`netlib` 生成 .so 但不跑 `tests`；⚠ 不要用 `["libs"]`——不生成 .so 导致 install 失败）。详见 `references/cmake-cross-compiler-install-pitfalls.md` §1 |
| **`install_root` 是死键** | Spack 1.x 的安装树根是 `config:install_tree:root:`（默认 `$spack/opt/spack`），`install_root:` 被**静默忽略**。实测：config.yaml 写 `install_root: $spack/var/opt`，包仍装到 `$spack/opt/spack/linux-aarch64/`。用 `spack config blame config` 确认生效键 |
| **`spack config get --scope=X` 只读 X scope** | 不是合并结果。用它导出的 `compilers.yaml`/`repos.yaml` 副本会是空文件，`packages.yaml` 只剩 site scope 几行。要完整生效配置用不带 `--scope` 的 `spack config get <section>`；查"谁覆盖了谁"用 `spack config blame <section>`。配置"看起来没写进去"时先怀疑读取范围 |
| **包自带 install.sh 的 `df` 空间检查** | HPCKit install.sh 比较 `bootstrapper.conf` 的 `software_size=10485760`(KB=10GB) 与 `df -k <prefix>` avail，avail 不足即拒（ext4 保留块吞 Avail 只是成因之一；检查对象=--prefix 路径，已实测）。解除：把有空闲的文件系统（或 tmpfs）挂到安装树根。tmpfs 重启丢数据（链接接入可幸存）；脚本重写 config.yaml 会致安装树视图回退，重跑前备份。详见 `references/spack-install-location-and-config-scope.md` |
| **install tree 换根后 DB 死记录** | 旧视图残留记录不自动失效 → `spack find` 多条、`spack location -i <pkg>` 报 matches multiple packages（裸调用拿空串+非零退出）。诊断：遍历 hash 查前缀 `! -d`；清理：`spack uninstall -y --force /hash...`（只删 DB 不删文件）。另注意包目录可能是 symlink（du 4.0K ≠ 空包）。Spack 1.x 编译器注册落在 `~/.spack/packages.yaml`（external 形式），site compilers.yaml 为空属正常；`Found no new compilers` 不是失败。详见 `references/spack-install-location-and-config-scope.md` |
| **本地 repo namespace 必须全小写** | 含大写（如 `kunpeng920F_workflow`）→ `Invalid namespace` 告警 + `spack repo list` 标 `[-]`；幂等注册检查按路径 grep 会误判「已注册」跳过修复，坏状态不自愈。修复：repo.yaml namespace 改小写后重注册。详见 `references/spack-install-gotchas.md` §4 |
| **builtin repo disabled 警告是良性的** | spack 1.2.1 tarball 不带 `var/spack/repos/builtin`，builtin 包由 bootstrap 副本（`~/.spack/package_repos/<id>/repos/spack_repo/builtin`）提供，包解析不受影响，勿追 |
| **spec 验证退出码别从管道取** | `spack spec ... \| grep ...; echo $?` 拿到的是 grep 的退出码；先 `spack spec ... > file 2>&1; RC=$?` 再 grep 文件。输出含 "Error" 字样未必失败（namespace 告警行也含），以 RC 为准 |
| **GCC 12+ DO 循环变量重定义** | elmerfem DCRComplexSolve.F90 报 `Index variable 'i' redefined`（issue #274）。**`-std=legacy` 无效**——这是 GCC 11+ 硬性检查。修复：`filter_file` 在受影响子程序加 `INTEGER :: i, n, NodeIndexes(:)`。上游 patch 因行号偏移无法直接 `patch()` 声明（9/9 hunks FAILED），须用 `filter_file` |
| **Flang 跨编译器 .mod 不兼容** | Flang（BiSheng）无法读取 GCC gfortran 编译的 `.mod` 文件（`F90-F-0004-Corrupt or Old Module file`）。spack concretizer 会复用 gcc 版 Fortran 依赖。修复：`spack install pkg %llvm ^netcdf-fortran %llvm` 强制同编译器。手动编译兜底：不传 netcdf 路径让 CMake FindNetCDF 自动禁用功能（详见 `references/cmake-cross-compiler-install-pitfalls.md` §3a）。诊断：`spack spec pkg %llvm \| grep fortran=`，依赖行显示 `%fortran=gcc` 即有问题 |
| **Flang 不支持 GCC 特有 flags** | `-fallow-argument-mismatch` 是 GCC 10+ 专有，Flang 报 `unknown argument`。为 `%llvm`/`%clang` 编译器设 Fortran flags 时不要加此 flag |
| **Clang 19+ implicit-function-declaration 是错误** | 旧式 C 代码缺少 `#include` 声明，GCC 只警告，Clang 19+ 报错。修复：`-DCMAKE_C_FLAGS=-Wno-error=implicit-function-declaration -Wno-error=implicit-int` |
| **CMake FindMKL.cmake 对 Flang FATAL_ERROR** | elmerfem 等项目在 BLAS/LAPACK 未显式设置时调 `FIND_PACKAGE(MKL QUIET)`，FindMKL.cmake 对 Flang 走 ELSE 分支 `MESSAGE(FATAL_ERROR)`（FATAL_ERROR 覆盖 QUIET）。修复：在 `cmake_args()` 显式设 `-DBLAS_LIBRARIES` 和 `-DLAPACK_LIBRARIES` 指向 openblas，跳过 MKL 探测块 |

---

## 参考文件路径

- Spack 内置包示例：`~/.spack/package_repos/*/repos/spack_repo/builtin/packages/`
- 本地仓库示例（HYCOM、Palabos、VASPKIT、SWMM、QDK、TVM、WanT、Cactus、ProteinMPNN、ProtTest、py-towhee、ParaFEM、FVCOM、PyRosetta、COPASI、PWDFT、Chaste 等）：`/root/lq/spack/my_pkgs/spack_repo/tutorial/packages/<pkg>/package.py`

## 参考文件索引

| 文件 | 内容 |
|------|------|
| `references/hmpi-ompi-cc-debugging.md` | hmpi OMPI_CC 注入缺失的完整 A/B 对照实验复现步骤 |
| `references/kml-library-structure-and-merging.md` | KML 库符号依赖表、合并方案分析、OMP 版本坑 |
| `references/kml-stdout-warning-pollution.md` | KML stdout 警告污染 meson 的诊断与修复 |
| `references/kml-isa-variants.md` | KML 多指令集变体（neon/sve/sve512/sve_no_f64mm/sme=matrix/noarch）的语义、CPU part 选路表、**向量长度不匹配导致静默算错**的实测数据与 `prctl` 修法、链接/装载坑、反汇编判据、实测性能、可复现验证配方 |
| `references/kalign-sve-optimization.md` | kalign SVE 优化实录：compiler-wrapper 绕过、-flto/-ffast-math 坑、libgomp vs libomp、容差 patch |
| `references/packages-yaml-config-gotchas.md` | 配置鲲鹏 kp-spack 仓库到已有 Spack 时的 packages.yaml 陷阱：多值变体 require 语法、all.compiler 废弃、hpckit 版本约束冲突、namespace 冲突、配置合并策略 |
| `references/spack-package-verification-gotchas.md` | 批量安装时包名/版本验证陷阱：通用名≠spack名（elmer→elmerfem）、LAMMPS 版本号格式不匹配（2Aug2023→20230802.4）、鲲鹏优化版 vs 原版选择、CSV 风格 .yaml 无法用 write_file 写入、builtin 包版本滞后上游（namd@3.0.3 实例）、manual_download 包 tarball 预置、workflow 阶段2 执行契约与报告模板 |
| `references/spack-install-gotchas.md` | 安装阶段 concretizer/编译器问题：BiSheng=`%llvm`、local_repo openblas 遮蔽 builtin、provider 列表跨 scope 合并、spack 1.2.1 仓库结构、cp2k conflicts `%clang`、openblas 测试失败 |
| `references/cmake-cross-compiler-install-pitfalls.md` | CMake 项目 gcc/llvm 双编译器安装陷阱：openblas `all`→`shared` 跳过 aarch64 SIGABRT 测试、GCC 12+ DO 循环变量重定义（`-std=legacy` 无效，须 `filter_file` 加局部声明）、Flang 跨编译器 .mod 不兼容（须 `^netcdf-fortran %llvm`）、Flang 不识别 `-fallow-argument-mismatch`、Clang 19+ implicit-function-declaration 为错误、FindMKL.cmake 对 Flang FATAL_ERROR（须显式设 BLAS_LIBRARIES） |
| `references/spack-install-location-and-config-scope.md` | 安装位置与配置生效语义：`install_root` 死键 / `install_tree: root:` 正确写法、`spack config get --scope=` 只读单 scope、install.sh `df` 空间检查机制实测（bootstrapper.conf software_size、--prefix 路径、两种触发模式）、DB 死记录清理、config.yaml 回退防护（备份→跑→恢复）、编译器注册落盘位置、tmpfs 易失性 |
