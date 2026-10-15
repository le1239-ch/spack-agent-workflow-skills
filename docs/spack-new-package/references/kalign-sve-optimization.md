# Kalign SVE 优化：编译器选择与 FP 语义调优实录

## 背景

kalign 3.3.2 在鲲鹏920上的性能优化。原 BiSheng clang + `-ffast-math` 方案导致 3 个算例（hpr/rhv/rvp）失败。需要在不使用 `-ffast-math` 的前提下实现 SVE 向量化加速。

## 关键发现

### 1. spack compiler-wrapper 静默禁用 SVE 自动向量化

**现象**：config.log 和 Makefile 中 CFLAGS 正确包含 `-mcpu=native`，但编译出的二进制 0 个 SVE 指令。

**A/B 验证**：
- spack wrapper 编译 `euclidean_dist.o` → 0 SVE 指令
- 直接用 HPCKit gcc 12.3.1 编译同一文件同一 CFLAGS → 8 SVE 指令
- 两者 .comment section 都标注 `GCC: (gcc for openEuler 3.0.2) 12.3.1`

**根因**：spack compiler-wrapper（`compiler-wrapper-1.1.0` 的 `libexec/spack/cc`）在传递 CFLAGS 到底层 gcc 的过程中，某些注入参数（可能是 `-isystem` 或 spack 注入的依赖路径参数）干扰了 GCC 的 SVE 自动向量化 pass。

**修复**：在 `setup_build_environment` 中直接设 `CC` 为 HPCKit gcc 绝对路径：
```python
gcc_dir = join_path(self.spec["hpckit"].prefix, "HPCKit", "25.1.0", "compiler", "gcc", "bin")
env.set("CC", join_path(gcc_dir, "gcc"))
```
修复后二进制 SVE 指令数从 0 → 112。

### 2. -flto 禁用 GCC SVE 自动向量化

控制变量实验（HPCKit gcc 12.3.1，同一 dot-product 源码）：

| CFLAGS | SVE 指令数 |
|--------|-----------|
| `-O3 -mcpu=native` | 5 |
| `-O3 -mcpu=native -ffast-math` | 5 |
| `-O3 -mcpu=native -ffp-contract=off` | 5 |
| `-O3 -mcpu=native -flto` | **0** |
| `-O3 -mcpu=native -ffast-math -flto` | **0** |

结论：鲲鹏920 上需要 SVE 自动向量化时，CFLAGS 中不要加 `-flto`。

### 3. -ffast-math 破坏精确浮点收敛循环

kalign `bisectingKmeans.c` 的 `split()` 函数用 `wl[j] != cl[j]` 判断 k-means 收敛。`-ffast-math` 允许 FMA 融合和运算重排，使 `wl[j] /= num_l` 的结果与 `cl[j]` 永远无法精确相等 → 收敛循环跑到 10000 次 → `ERROR_MSG("Failed.")` → 程序挂起。

**三种 FP 模式对比（kalign hpr 算例，3349 序列）：**

| CFLAGS | FMA | IEEE 比较 | 收敛 | hpr 结果 |
|--------|-----|-----------|------|---------|
| GCC 默认 | ✅ | ✅ | ✅ | 0.32s OK |
| `-ffast-math` | ✅ | ❌ | ❌ | 挂起 FAILED |
| `-ffp-contract=off` | ❌ | ✅ | ✅ | 0.35s OK（但整体慢） |

**最优方案**：GCC 默认 FP 语义（不设 `-ffast-math` 也不设 `-ffp-contract=off`）+ 容差 patch 作为安全网。

### 4. libgomp (GCC) vs libomp (BiSheng) OpenMP 开销

同一 kalign p450 算例（21013 序列，8 线程）的 perf profile：

| 编译器 | OpenMP 运行库 | OpenMP 开销占比 | 计算热点占比 |
|--------|-------------|---------------|------------|
| BiSheng clang 17 | libomp.so | **60%** | 14.6% (aln_profileprofile) |
| GCC 12.3.1 | libgomp.so | **~0%** | 48.7% (aln_profileprofile) |

BiSheng 的 libomp 在 OpenMP task + taskwait + nested parallel 场景下调度开销极大。GCC 的 libgomp 对同样的代码几乎零开销。

**结论**：OpenMP task 密集型应用在鲲鹏920上应优先使用 GCC + libgomp，避免 BiSheng + libomp。

### 5. GCC 12.3.1 SVE 自动向量化能力

HPCKit 的 GCC 12.3.1（`/opt/HPCKit/25.1.0/compiler/gcc/bin/gcc`）能自动生成 SVE 512-bit 指令（`whilelo`、`ld1w z`、`fadda`、`fmla z`），但系统 GCC 10.3.1（`/usr/bin/gcc`）只能生成 NEON 128-bit 指令。

验证：
```bash
echo 'float dot(float* a, float* b, int n){float s=0;for(int i=0;i<n;i++)s+=a[i]*b[i];return s;}' > /tmp/dot.c
# GCC 10.3.1: fmul v + fadd s (NEON 128-bit)
# GCC 12.3.1: whilelo + ld1w z + fadda (SVE 512-bit)
```

## 最终 package.py CFLAGS 配置

```python
env.set("CC", join_path(gcc_dir, "gcc"))  # 绕过 spack wrapper
env.set("CFLAGS", " ".join([
    "-O3",
    "-mcpu=native",          # SVE 512-bit 自动向量化
    "-funroll-loops",
    "-ftree-vectorize",
    "-finline-functions",
    "-fopenmp",              # libgomp (低开销)
    # 不加 -ffast-math: 保持 IEEE 比较语义
    # 不加 -ffp-contract=off: 保留 FMA (性能)
    # 不加 -flto: 不禁用 SVE 向量化
]))
```

## 验证检查清单

1. `objdump -d $(which kalign) | grep -cE "whilelt|whilelo|ld1w.*z|fmla.*z|fadda.*z"` → 应 > 100
2. `ldd $(which kalign) | grep gomp` → 应链接 libgomp.so
3. 之前失败的算例（hpr/rhv/rvp）全部成功
4. `strings $(which kalign) | grep -c "Failed\."` → 容差 patch 生效后应为 0 或仅来自非关键路径
