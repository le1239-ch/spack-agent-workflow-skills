# cmaq

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | cmaq |
| 版本 | 5.3.1 |
| 编译器 | gcc@12.3.1 |
| hash | mznbwizrvwo65erq65mwl7s66jqvvqjc |
| 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/cmaq-5.3.1-mznbwiz |
| 主页 | https://www.epa.gov/CMAQ |

## 描述

Code base for the U.S.
无描述

## 安装命令

```bash
# 加载 spack 环境
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh

# 精确复现本实例（推荐：hash 唯一定位，避免同包多版本/多编译器歧义）
spack install /mznbwiz

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install cmaq@5.3.1 gcc@12.3.1

# 加载使用
spack load /mznbwiz
```

## 依赖树

```
-- linux-openeuler22-aarch64 / %c,fortran=gcc@12.3.1 ------------
cmaq@5.3.1
    compiler-wrapper@1.1.0
    gcc@12.3.1
    gcc-runtime@12.3.1
    glibc@2.34
```

## 加载方式

```bash
spack load /mznbwiz
```

或通过 module：

```bash
module load cmaq
```
