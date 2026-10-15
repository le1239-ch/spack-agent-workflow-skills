# KML 库 stdout 警告污染 meson run_command

## 问题现象

在 HPCKit 生态下构建使用 meson 构建系统的 Python 包（如 py-scipy、py-numpy@1.26+）时，
meson 的 `run_command()` 调用 Python 解释器（`import numpy` / `import pythran` / `f2py -v`），
其 stdout 会被 KML 库的初始化警告污染，导致 meson 把警告文本当作路径或版本号，构建失败。

## 根因

KML 的 `libkblas.so` 在动态加载初始化时，会检查 `/usr/lib64/libsdma_dk.so`（SDMA/HBM 加速库）。
当该库不存在时，KML 向 **stdout**（不是 stderr）打印：

```
Warning: libsdma_dk.so under '/usr/lib64' is not found or some sdma functions are not loaded success, HBM memory buffer will be not used in later calculation.
```

这个警告出现在**每次** `import numpy`（因为 numpy 的 C 扩展链接了 libkblas.so）时，
且无法通过以下环境变量抑制（均已实测验证无效）：

| 环境变量 | 值 | 效果 |
|----------|-----|------|
| `KML_BLAS_USE_HBM` | `0` | 无效，警告仍出现 |
| `KML_BLAS_NOT_USE_HBM` | `1` | 无效，反而多打一行 deprecation 警告 |
| `KML_BLAS_SDMA_SO_PATH` | `""` | 无效，警告仍出现 |

## 受影响的 meson run_command 场景

在 scipy 1.16.x 的 `scipy/meson.build` 中，至少有 3 处 `run_command` 受影响：

1. **numpy include 路径**（`meson.build:63,80`）
   - `run_command(py3, ['-c', 'import numpy; print(numpy.get_include())'])`
   - stdout = `"Warning: libsdma...\n/actual/path"`
   - `include_directories(incdir_numpy)` 失败（路径含警告文本）

2. **pythran include 路径**（`meson.build:109`）
   - `run_command(py3, ['-c', 'import pythran; print(pythran.get_include())'])`
   - 同样的 stdout 污染

3. **f2py 版本检查**（`meson.build:211`）
   - `run_command([f2py, '-v'])`
   - f2py 脚本内部 import numpy → 触发 KML 初始化 → 警告污染 stdout
   - stdout = `"Warning: libsdma...\n1.25.2"`
   - 版本字符串解析失败：`Problem encountered: Found f2py executable is too old: Warning: libsdma...`

## 诊断方法

```bash
# 检查 meson-log.txt 中的 run_command stdout
grep -A5 "Running command" <stage>/build/meson-logs/meson-log.txt | grep "Warning.*libsdma"

# 如果看到 Warning 文本混入路径/版本输出，即为此问题
```

## 修复方案（部分已验证）

### 方案 A：通过 meson native file 提供 external property（已验证，适用于 include 路径）

meson 的 `meson.get_external_property('numpy-include-dir', 'not-given')` 会从 native file
的 `[properties]` section 读取。提供该属性后，meson 跳过 `run_command`，直接使用给定路径。

在 PythonPackage 的 `config_settings()` 中：

```python
def config_settings(self, spec, prefix):
    # ... 计算 numpy_include 和 pythran_include 绝对路径 ...

    native_file = os.path.join(self.stage.source_path, "spack-numpy-native.ini")
    with open(native_file, "w") as f:
        f.write("[properties]\n")
        f.write(f"numpy-include-dir = '{numpy_include}'\n")
        f.write(f"pythran-include-dir = '{pythran_include}'\n")

    return {
        "builddir": "build",
        "setup-args": {
            "-Dblas": blas,
            "-Dlapack": lapack,
            "--native-file": native_file,
        },
    }
```

**注意：** meson-python 自己也会生成一个 native file（`build/meson-python-native-file.ini`），
两个 native file 可以共存（meson 接受多个 `--native-file` 参数，后者覆盖前者的同名属性）。

### 方案 B：patch meson.build 过滤警告行（适用于 f2py -v 等命令输出）

对于 `f2py -v` 这类无法通过 external property 绕过的 run_command，需要在 `install()` 方法中
patch `scipy/meson.build`，过滤掉 stdout 中的 `Warning:` 行。

由于 meson 的 `run_command().stdout()` 返回原始字符串，无法在 meson 层面直接过滤，
需要在 Python 脚本层面处理，或 patch meson.build 将 `.stdout().strip()` 改为取最后一行。

### 方案 C：py-numpy 的 setup_run_environment 注入 KML 库路径（已验证）

py-numpy 的编译扩展（`_multiarray_umath.so` 等）链接了 `libkblas.so`，后者又 NEEDED `libkm.so`。
如果不注入 KML 库路径到 `LD_LIBRARY_PATH`，`spack load py-numpy` 后 `import numpy` 会失败：
`libkm.so.1: cannot open shared object file`。

```python
def setup_run_environment(self, env):
    spec = self.spec
    # kpblas 的 ISA 专用库目录（libkblas.so）
    for lib_dir in spec["kpblas"].libs.directories:
        env.prepend_path("LD_LIBRARY_PATH", lib_dir)
    # kplapack 的 ISA 专用库目录（libklapack.so）
    for lib_dir in spec["kplapack"].libs.directories:
        env.prepend_path("LD_LIBRARY_PATH", lib_dir)
    # KML 通用目录（libkm.so 在 noarch/ 下）
    kpblas_spec = spec["kpblas"]
    hpckit_spec = kpblas_spec["hpckit"]
    kml_prefix = os.path.join(
        hpckit_spec.prefix, "HPCKit", str(hpckit_spec.version),
        "kml", kpblas_spec.variants["compiler_variant"].value,
    )
    for sub in ("lib", os.path.join("lib", "noarch")):
        kml_lib_dir = os.path.join(kml_prefix, sub)
        if os.path.isdir(kml_lib_dir):
            env.prepend_path("LD_LIBRARY_PATH", kml_lib_dir)
```

**注意：** 即使 `setup_run_environment` 正确注入了 KML 路径（numpy 可以 import），
KML 警告**仍然**会打印到 stdout。所以方案 C 解决的是 runtime import 失败问题，
不解决 meson 构建期的 stdout 污染问题。两者是独立的问题。

## KML 库路径速查

```
<hpckit_prefix>/HPCKit/<version>/kml/<compiler_variant>/
├── include/                  # KML 头文件
└── lib/
    ├── noarch/
    │   └── libkm.so           # KML 通用运行时（所有 ISA 共享）
    ├── neon/kblas/<mode>/     # neon 版 libkblas.so
    ├── sve/kblas/<mode>/      # sve 版 libkblas.so
    ├── sve512/                # libklapack.so, libklapack_full.so, libksvml.so 等
    └── sme/kblas/<mode>/      # sme 版 libkblas.so
```

`<mode>` = kpblas 的 kblas_mode variant（multi/locking/nolocking，默认 multi）。

## spack 1.1.1 的 package_hash 机制

spack 1.1.1 的 spec hash 包含 `package_hash`（package.py 内容的哈希）。
修改 package.py 会改变 spec hash，导致已安装的包被重新构建。
这在调试时是优势（修改立即生效），但也意味着修改 py-numpy 的 package.py 会触发
py-numpy 重新安装（耗时较长）。

```bash
spack find --json py-numpy@1.25.2 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["spec"].get("package_hash","?"))'
```
