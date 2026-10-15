# 阶段 4 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的可直接执行指令。Agent 读取此文件后，按步骤执行即可完成阶段4。

---

## 指令

你是鲲鹏920F HPC 软件栈部署工作流的阶段4执行 Agent。你的任务是对性能关键包用 KML 数学库重编，注入鲲鹏920优化 flag。

> ⛔ **禁止自行修改任何 .md 文件**（如 compile_opt_log.md、DESCRIPTION.md 等）。如需修改，必须先向用户说明并获同意。脚本自动生成的 .md 不受此限。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 前置条件

- 阶段3已完成（`install_log.md` 中有成功安装的包）
- Spack 环境已加载（`source $SPACK_DIR/share/spack/setup-env.sh`）

### 输入文件

- `stage3-install/install_log.md` — 确认已安装的包
- `stage1-setup-spack/packages.yaml` — 基础配置

### 执行方式

直接运行脚本：

```bash
cd /home/zhangyuhang/workflow/stage4-compile-opt
bash compile_opt.sh
```

或指定特定包重编：
```bash
bash compile_opt.sh petsc gromacs
```

脚本会自动对性能关键包列表中的包执行 `--fresh` 重编，注入 KML 数学库。

### 优化策略

**只改 flags，不改配方。** 对性能关键包用 **provider 约束**重编，把 BLAS/LAPACK 指向鲲鹏数学库：`^kpblas ^kplapack`（二者真实 `provides("blas")` / `provides("lapack")`）。

> ⚠ **切勿用 `^kpkml`**（实测不可行）：`kpkml` 是元包、无 `provides()` —— `spack spec <pkg> ^kpkml` 报 `'kpkml' is not a possible dependency of any root spec`；`packages:blas:require:kpkml` 同属毒行，会让所有 concretization 报 `cannot satisfy a requirement for package 'blas'`。详见 `compile_opt_log.md` 注4。

#### BiSheng 鲲鹏920 推荐 flag

```
-O3 -mcpu=tsv110 -march=armv8.2-a
```

**⚠ SVE 优化注意事项（实测经验；全量见 `docs/spack-new-package/SKILL.md` 阶段十 与 `references/kalign-sve-optimization.md`）：**

| 问题 | 后果 | 规避 |
|------|------|------|
| -flto 禁用 GCC SVE 向量化 | SVE 指令消失 | **不要加 -flto** |
| -ffast-math 破坏浮点收敛循环 | 程序挂起/崩溃 | **不设 -ffast-math**，GCC 默认 FP 语义最优 |
| spack compiler-wrapper 静默禁用 SVE | wrapper 传了 `-mcpu=native`，编译产物却 **0 条** SVE 指令 | **绕过 wrapper**：在 `setup_build_environment` 里把 `CC`/`CXX` 设为 HPCKit gcc 绝对路径（实测修复后二进制 SVE 指令 100+）；接受默认行为＝白丢 SVE |
| libgomp vs libomp | OpenMP task 密集型 60%+ 开销 | task 密集型优先 GCC（libgomp） |

### 参考文档

- **Spack 打包/调优知识库（工作流内全量副本，权威）**：`/home/zhangyuhang/workflow/docs/spack-new-package/`
  - `SKILL.md` — 总纲（阶段三 KML 计算库依赖声明与目录布局、阶段八 运行时环境注入、阶段十 构建与性能坑、关键规则速查）
  - `references/kml-isa-variants.md` — **重编注入 KML 必读**：KML ISA 变体（neon/sve/sve512/sve_no_f64mm/matrix）目录选路、VL 不匹配静默算错、`prctl` 设置
  - `references/kalign-sve-optimization.md` — SVE 优化实测（spack compiler-wrapper 绕过、`-flto`/`-ffast-math` 坑、libgomp vs libomp、容差 patch）
  - `references/hmpi-ompi-cc-debugging.md` — hmpi 缺 OMPI_CC 注入 → 链接正确性（编译器版本 / rpath 丢失）
  - `references/kml-library-structure-and-merging.md` — KML 库结构与合并
  - `references/spack-install-gotchas.md` — 安装期 concretizer/编译器坑（BiSheng=`%llvm`、provider 列表跨 scope 合并、local_repo 遮蔽 builtin）
  - `references/spack-install-location-and-config-scope.md` — 安装位置与配置生效语义（`--scope=site` 写入路径、install_tree root、DB 死记录、`df` 空间检查）
- 速查版：`/home/zhangyuhang/workflow/docs/spack_package_guide.md`
- 已知坑速查表：`docs/failure_handling.md`

### 性能关键包列表

| 包名 | 原因 | 优化约束 |
|------|------|---------|
| fftw | FFT 核心库 | +mpi+openmp |
| scalapack | 并行 BLAS | ^kpblas ^kplapack |
| petsc | 线性求解器 | +mpi+hdf5+mumps+hypre ^kpblas ^kplapack |
| gromacs | MD 应用 | +mpi~cuda ^kpblas ^kplapack |
| lammps | MD 应用 | +mpi+manybody+molecule ^kpblas ^kplapack |
| openfoam | CFD 应用 | ^kpblas ^kplapack |
| quantum-espresso | 量子化学 | +mpi+hdf5 ^kpblas ^kplapack |
| cp2k | 量子化学 | +mpi+libint+libxc ^kpblas ^kplapack |

> **KML 约束形式**：`^kpkml` 不可用（元包无 `provides()`），已按 stage4 实测改为 `^kpblas ^kplapack`；FFT / ScaLAPACK 场景对应的 KML 包为 `kpfftw` / `kpscalapack`，stage4 未实测采用（见 `compile_opt_log.md` 注4）。

> **注意**：只对实际已安装的性能关键包重编。install_log.md 中没有的包跳过。

### 失败处理

1. **带 `^kpblas ^kplapack` 约束重编失败** → 去掉该约束重试1次（回落官方 recipe）
2. **去掉约束仍失败** → 记录 ❌ 跳过，不影响其他包
3. **超时** → 每包最长 1 小时，超时记为失败

### 完成标志

- `compile_opt_log.md` 中每个性能关键包都有记录（✅ 重编成功 或 ❌ 跳过）
- 成功重编的包 `spack find -l <包名>` 可查到新 hash
