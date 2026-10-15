# Spack 包名与版本验证陷阱

> 本文件记录在批量安装 HPC 软件时，验证 spack 包名和版本号时遇到的常见陷阱与修正方法。

## 场景

用户在 `packages_to_install.yaml` 中列出待安装软件（格式：`软件名,版本(可选),编译器(gcc/bisheng/both)`），需要逐个验证包名在 spack 中是否存在、指定版本是否可用。

## 验证流程

```bash
# workflow 部署机的实例（多个 spack 实例共存时先确认用哪个！）
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh

# 1. 验证包名存在
spack info <pkg>        # 存在则输出包信息，不存在则报错

# 2. 搜索包名（当 spack info 失败时）
spack list "<pkg>*"     # 模糊搜索，找到正确包名

# 3. 验证指定版本
spack info <pkg> | grep -A 20 "Versions:"   # 查看 Safe versions 列表
spack versions <pkg>                         # 查看所有可用版本（含远程）
#    指定版本不在 Safe versions 时：先确认上游是否真发过该版本
#    （builtin 包常滞后上游数月，见陷阱 6），不要直接判"清单填错"

# 4. 验证 spec 解析（两种编译器都要验，编译器名必须用 spack 里的实际注册名）
spack spec <pkg>@<version> %gcc@<gccver>     # 应无报错
spack spec <pkg>@<version> %llvm@<llvmver>   # bisheng 在 spack 中注册为 llvm
```

### 编译器名：清单里的 `bisheng` ≠ spec 里的 `%bisheng`

`packages_to_install.yaml` 的第三列写 `bisheng`，但 spack 里**没有名为 `bisheng` 的编译器**。BiSheng 是以 clang/flang 二进制注册在 `llvm` 外部包里的（实测 `llvm@19.1.7` 的 prefix 指向 HPCKit 的 `compiler/bisheng`，`clang --version` → `BiSheng Enterprise ... clang version 19.1.7`）。

```bash
$ spack spec <pkg>@<ver> %bisheng
==> Error: '<pkg>@<ver> %bisheng' cannot depend on bisheng
```

**验证阶段要做两件事**：
1. 用 `%llvm@<ver>` 代替 `%bisheng` 验证 spec 能解析；
2. 把"清单第三列的 `bisheng` 需要映射为 `%llvm@<ver>`"作为**交接项**写进报告。

**历史实测（2026-09 上旬，旧版批量安装脚本）**：脚本对 `bisheng`/`both` 条目硬拼 `%bisheng` 传给 spack，`spack spec` 校验阶段即报 `cannot depend on bisheng` 写入 ❌ install_log；且其 A2 重试逻辑重新拼接**同样的** `%bisheng` spec，重试救不回（3 次全败）。

**现状实测（2026-09-28，workflow 部署机 stage3-install/install_batch.sh）**：该脚本**已内置** bisheng→`%llvm` 映射（第 161/184/357 行），清单填 `both`/`bisheng` 可直接展开为 `%gcc` + `%llvm` 两腿，无需清单侧规避。**拿到新部署机/新脚本时仍先 `grep -n bisheng install_batch.sh` 确认有无映射，不要假设**——此类结论绑定具体脚本版本。

修法（针对仍硬拼 `%bisheng` 的脚本，二选一）：
- **脚本侧（一劳永逸）**：在安装脚本拼 spec 处把 `%bisheng` 映射为 `%llvm`（脚本通常多处拼接，需全部覆盖）；
- **清单侧（最小改动）**：清单只填 `gcc`，放弃 bisheng 腿（代价：少一个编译器变体）。

先用 `spack compiler list` 确认实际注册名，不要假设。

## 陷阱 1：软件通用名 ≠ spack 包名

| 用户写的通用名 | spack 实际包名 | 说明 |
|---------------|---------------|------|
| `elmer` | `elmerfem` | Elmer FEM 求解器，spack 中包名为 `elmerfem` 而非 `elmer` |
| `espresso` | `quantum-espresso` | Quantum ESPRESSO，spack 用全名 |
| `openfoam` | `openfoam` | 这个是对的，但需注意有多个版本分支 |

**修正方法**：用 `spack list "elmer*"` 模糊搜索找到正确的 spack 包名。

## 陷阱 2：版本号格式不匹配

LAMMPS 的官方发布版本名是 `2Aug2023`（日期格式 `DDmmmYYYY`），但 spack 使用的版本号格式是 `YYYYMMDD.N`（数字格式 + 更新序号）。

| 软件的官方版本名 | spack 版本号 | 转换规则 |
|----------------|-------------|---------|
| LAMMPS `2Aug2023` | `20230802.4` | 日期转 `YYYYMMDD` + `.N`（N 为 update 序号） |
| LAMMPS `29Aug2024` | `20240829.4` | 同上 |
| LAMMPS `23Jun2022` | `20220623.4` | 同上 |

**LAMMPS 版本号对照规则**：
- 官方 `stable_<DDmmmYYYY>_update<N>` → spack `YYYYMMDD.N`
- `stable_2Aug2023_update4` → `20230802.4`
- `stable_29Aug2024_update4` → `20240829.4`
- 不带 update 的稳定版 `stable_<DDmmmYYYY>` → `YYYYMMDD`（无 `.N` 后缀）

**修正方法**：用 `spack info lammps | grep -A 30 "Safe versions:"` 查看 spack 支持的版本号列表。

## 陷阱 3：鲲鹏优化版 vs 原版包的选择

某些软件在鲲鹏 repo（kunpeng920prof）中同时存在优化版和原版：

| 软件原版 | 鲲鹏优化版 | 区别 |
|---------|-----------|------|
| `elmerfem` | `elmer-opt` | elmer-opt 用 bisheng + hmpi 构建，依赖 OpenBLAS；elmerfem 是标准 CMakePackage |
| (通用) | `lammps_opt` | 鲲鹏优化版 LAMMPS |
| `gromacs` | `gromacs_opt`（aitiaoyou_work repo） | 优化版存在于本地第三方 repo，通用名解析到 builtin |

**选择策略**：
- 用户要求 `both`（gcc + bisheng）→ 用原版包（如 `elmerfem`），优化版通常仅支持单一编译器
- 用户要求单一编译器且该编译器是 bisheng → 可考虑优化版（如 `elmer-opt`）
- 优化版通常硬编码 bisheng 编译器路径，不适合 gcc 编译
- 注意本地 repo 的同名/优化版包会改变解析结果，报告中注明条目实际解析到哪个 repo 的哪个包

## 陷阱 4：spec 解析失败 —— 先确认是哪台 spack 实例，不要照搬上一轮结论

**曾出现的现象**：`elmerfem@9.0` 的 spec 解析报错 `No such variant 'threads' in package openblas`，虽然包名和版本都正确。

**该现象在 Spack 1.2.1 + `openblas@0.3.30` 下不复现**：同一 spec 干净解析，openblas 解析为 `openblas@0.3.30 ... threads=none`（变体存在）。上一轮结论对应的是更老的实例（openblas 0.3.18，且当时有本地 repo 的 openblas 遮蔽 builtin）。

**教训（通用）**：spec 解析失败这类结论**绑定 spack 实例 + 依赖包版本**。复验前先确认：

```bash
which spack && spack --version          # 同一台机器上可能存在多个 spack 实例！
spack location -i openblas 2>/dev/null  # 确认实际参与 concretize 的版本
spack spec <pkg>@<ver> %gcc@<ver>       # 用当前实例重跑，不要引用历史报错
```

鲲鹏场景下常见多实例共存（如 `$WORKFLOW/spack-workflow/spack-1.2.1` 与遗留的 `~/spack-1.2.1`），**历史报告里的报错可能属于另一个实例**。

**处理原则**：若重跑仍失败，属安装阶段（stage3）问题，**不应阻塞**包名/版本验证阶段（stage2）——在报告中记录并交接即可。

## 陷阱 5：write_file/patch 无法写入 CSV 风格的 .yaml 文件

`packages_to_install.yaml` 虽然扩展名是 `.yaml`，但实际内容是注释 + CSV 风格的行（如 `gromacs` / `lammps,20230802.4`），不是标准 YAML 键值对。

Hermes 的 `write_file` 和 `patch` 工具会对 `.yaml` 文件做 YAML 语法校验，CSV 风格的行（如 `elmerfem,9.0,both`）会被解析为标量导致 YAML 校验失败。

**报错信息**：
```
YAMLError: expected '<document start>', but found '<scalar>'
  in "<unicode string>", line 27, column 1:
    elmerfem,9.0,both
    ^
```

**解决方法**：使用 `terminal` 工具通过 `cat > file << 'EOF'` heredoc 写入，绕过 YAML 校验。

```python
from hermes_tools import terminal
content = "gromacs\nlammps,20230802.4\n..."
result = terminal(
    command=f"cat > /path/to/packages_to_install.yaml << 'ENDOFFILE'\n{content}\nENDOFFILE",
    timeout=10
)
```

## 陷阱 6：builtin 包版本落后上游 —— "No version exists" ≠ 包不存在

**实例（2026-09-28）**：清单填 `namd,3.0.3,both`。`spack info namd` 成功（包存在），但：

```bash
$ spack spec namd@3.0.3 %gcc
==> Error: No version exists that satisfies these input specs:
```

`spack info namd` 的 Safe versions 只有 `3.0.1 / 2.14 / 2.13 / 2.12`。web_search 确认上游 NAMD 3.0.3 已于 2026-07 发布——builtin 包未跟进（滞后约 2 个月）。`namd@3.0.1` 的 `%gcc`/`%llvm` spec 解析均通过（降级备选可用）。

**诊断流程**（spec 报 No version exists 时）：

```bash
spack info <pkg> | grep -A 20 "Safe versions:"   # 确认包内最高版本
# web_search "<pkg> <ver> release" 确认上游是否真的发过该版本
spack spec <pkg>@<最近可用版本> %gcc              # 验证降级备选可解析
```

**处理路径**：
- 降级到 builtin 支持的最近版本（改清单需用户确认）；
- 保留原条目，交下一阶段写 package.py 或手动编译（workflow AI_INSTRUCTION 的设计路径："不存在则阶段3 Agent 会编写 package.py 或手动编译"）；
- 多版本共存没有问题：同一清单可并列 `gromacs,2025.3,both` + `gromacs,2024.6,both`，spec 各自解析通过。

**教训**：包名验证（`spack info`）与版本验证（`spack spec`）是两回事，都要做；版本失败先区分"包不存在"还是"builtin 滞后上游"，结论与备选路径写进交接报告。

## 陷阱 7：manual_download（license 限制）包 —— tarball 必须预先手动放置

**实例（2026-09-28）**：builtin `namd` 包声明 `manual_download = True` 且 `redistribute(source=False, binary=False)`（NAMD license 要求官网注册下载），版本 URL 写成：

```python
url = "file://{0}/NAMD_2.12_Source.tar.gz".format(os.getcwd())
```

即 spack 在**执行安装命令时的 CWD** 找 tarball（下载 URL 随 builtin 包内置，`file://` 指向安装发起目录）。实测部署机上无任何 `NAMD_*_Source.tar.gz`，阶段3 直接安装必然在获取源码一步失败。

**stage2 预检动作**（清单含此类包时）：

```bash
# 定位包的 package.py（多 repo 共存时逐 repo 查）
grep -rln "class Namd" ~/.spack/package_repos/*/repos/spack_repo/builtin/packages/ 2>/dev/null
grep -nE 'manual_download|url =|version\(' <package.py 路径> | head -20

# 确认 tarball 是否已在盘上
find /root /home /opt /tmp -maxdepth 4 -iname 'NAMD_*Source*' 2>/dev/null
```

**交接要点**（写进验证报告）：(a) 需用户从官网手动下载对应版本 tarball；(b) 放置位置 = 批量安装脚本的执行 CWD（或由阶段3改 package.py 用绝对 `file://` 路径）；(c) tarball 版本须与清单一致。

## 阶段2 执行契约注意事项（workflow 场景）

- 清单 `packages_to_install.yaml` 是**用户手填**的：未经用户确认不得代改（删条目、降版本都算）。决策类询问超时未响应时，保守保留原条目，把问题与处理路径写进验证报告交给下一阶段。
- `package_verification.md` 自述"由 stage2-packages 执行生成"，属自动生成的 .md，每次执行可整体重写；`AI_INSTRUCTION.md` / `DESCRIPTION.md` 是固定指令文件，执行前后必须完全一致（用 mtime 核验）。
- 顺带核验下一阶段脚本的兼容性（如 bisheng→llvm 映射、清单解析逻辑），把结论写进报告，减少阶段3返工。
- 完成标志核验：非注释非空条目数 ≥ 1（`grep -cvE '^\s*#|^\s*$' packages_to_install.yaml`）。

## 验证报告模板

验证完成后应生成报告，包含以下内容：

```markdown
## 包名验证

| 软件名 | spack 中存在 | 包类型 | 说明 |
|--------|-------------|--------|------|
| gromacs | ✅ | CMakePackage | ... |
| elmer | ❌ | — | 修正为 elmerfem |

## 版本验证

| 软件名 | 指定版本 | spack 中可用 | 验证结果 |
|--------|---------|-------------|---------|
| gromacs | （最新） | 2026.1 | ✅ |
| lammps | 20230802.4 | 20230802.4 | ✅ |
| namd | 3.0.3 | ❌ builtin 最高 3.0.1 | 滞后上游，见遗留问题 |

## 遗留问题（交接下一阶段）

| 问题 | 影响 | 建议处理 |
|------|------|---------|
| namd@3.0.3 builtin 无此版本 | spec 解析失败 | 降级 3.0.1 / 阶段3写 package.py |
| NAMD tarball 不在盘上（manual_download） | 阶段3获取源码失败 | 官网下载放入安装脚本 CWD |

## 修正说明

| 原始内容 | 修正后 | 修正原因 |
|---------|--------|---------|
| elmer,9.0,both | elmerfem,9.0,both | spack 无 elmer 包名 |
| lammps,2Aug2023 | lammps,20230802.4 | spack 版本号格式不同 |
```
