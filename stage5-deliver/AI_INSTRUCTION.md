# 阶段 5 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的指令。

---

## 指令

你是阶段5执行 Agent。你的任务是为每个已安装软件生成说明文档。

> ⛔ **禁止自行修改任何 .md 文件**（如已有的 `<软件名>.md`、DESCRIPTION.md 等）。如需修改，必须先向用户说明并获同意。脚本（deliver.sh）自动生成的 .md 不受此限。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 前置条件

- Spack 环境已加载（推荐用工作流统一入口，会一并隔离 user scope）：
```bash
source /home/zhangyuhang/workflow/scripts/spack-env.sh
```
- 阶段3已完成（`install_log.md` 中有成功安装的包）

### 执行方式

直接运行脚本：

```bash
bash /home/zhangyuhang/workflow/stage5-deliver/deliver.sh
```

脚本会自动读取 `install_log.md`，对每个成功安装的软件生成一个 `<软件名>.md` 文件。

### 每个软件的文档内容

```markdown
# <软件名>

## 基本信息
| 项目 | 值 |
|------|-----|
| 软件名 | gromacs |
| 版本 | 2023.3 |
| 编译器 | %gcc |
| hash | abc1234 |
| 安装路径 | /opt/spack/.../gromacs/... |
| 主页 | https://www.gromacs.org |

## 描述
分子动力学模拟软件包...

## 鲲鹏优化组件
本软件已链接以下鲲鹏920优化组件（从依赖树中自动提取）：
| 组件 | 功能 |
|------|------|
| hmpi | 鲲鹏优化MPI通信库 |
| kpkml | KML元包(聚合BLAS/LAPACK/FFT/向量等子组件) |
| ... | ...(根据实际依赖树输出) |

## 安装命令
spack install gromacs@2023.3 %gcc
spack install gromacs@2023.3 %bisheng

## 依赖树
spack deps gromacs 输出...

## 加载方式
spack load gromacs
```

> 鲲鹏优化组件章节由 `deliver.sh` 自动从 `spack deps` 输出中提取，匹配14个鲲鹏包名（hmpi/hpckit/kpblas/kpspblas/kplapack/kpscalapack/kpscasolver/kpsolver/kpfft/kpfftw/kpvml/kpksvml/kpkupl/kpkml）。

### 手动安装的包

对于手动编译安装的包（spack find 找不到的），脚本会跳过。如果需要为其生成文档，手动创建：

```bash
cat > $SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/README.md << 'EOF'
# <pkg_name>

## 基本信息
| 项目 | 值 |
|------|-----|
| 软件名 | <pkg_name> |
| 版本 | <version> |
| 编译器 | gcc (手动编译) |
| 安装路径 | $SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install |

## 描述
<软件描述>

## 安装命令
cd $SPACK_WORKFLOW_DIR/manual-build/<pkg_name>
source <hpckit>/HPCKit/<ver>/setvars.sh --use-gcc
./configure --prefix=$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install
make -j$(nproc) && make install

## 加载方式
export PATH=$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install/bin:$PATH
export LD_LIBRARY_PATH=$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install/lib:$LD_LIBRARY_PATH
EOF
```

### 完成标志

每个已安装软件都有对应的 `.md` 文件，包含安装命令、依赖树、描述。
