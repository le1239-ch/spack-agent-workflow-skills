# 环境报告模板

> 由 setup_spack.sh 自动生成，请勿手动编辑。

| 项目 | 值 |
|------|-----|
| 架构 | aarch64 |
| CPU 型号 | Kunpeng 920 |
| 总核数 | 128 |
| NUMA 节点数 | 16 |
| 操作系统 | openEuler 22.03 LTS-SP4 |
| Spack 版本 | 1.2.1 |
| Spack 安装路径 | workflow/spack-workflow/spack-1.2.1 |
| Spack 配置目录 | workflow/spack-workflow/spack-1.2.1/etc/spack |
| 由工作流安装 | true/false |
| kp-spack repo 路径 | workflow/spack-workflow/kp-spack-repo/.../kunpeng920prof |
| 鲲鹏 repo 挂载验证 | ✅ spack info hpckit 成功 |
| spack spec 验证 | ✅ hpckit spec 解析成功 |
| HPCKit 状态 | 已安装 |
| HPCKit 安装路径 | <spack_install_prefix> |
| 编译器注册 | ✅ gcc + bisheng 已注册 |
| BiSheng 路径 | <hpckit_prefix>/.../compiler/bisheng/bin |
| BiSheng 版本 | 4.1.2 |
| HPCKit 环境路径 | <hpckit_prefix> |
| GCC 版本 | 12.3.1 |
| HMPI mpicc | mpicc --showme 输出 |
| 鲲鹏KML组件 | hmpi hpckit kpblas kpspblas kplapack kpscalapack kpscasolver kpsolver kpfft kpfftw kpvml kpksvml kpkupl kpkml |
| kqmalloc | /usr/local/ksl/lib/libkqmalloc.so |

## CPU 详细信息
（lscpu 输出）

## NUMA 拓扑
（numactl -H 输出）

## Spack 配置来源
（spack config list 输出）

## 当前 repos.yaml
（repos.yaml 内容）

## 当前 packages.yaml
（packages.yaml 内容）

## 通过条件检查

| 条件 | 状态 |
|------|------|
| target=aarch64 | ✅ |
| Spack 可用 | ✅ |
| kp-spack repo 已挂载 | ✅ |
| spack info hpckit 成功 | ✅ |
| HPCKit 已安装 | ✅ |
| 编译器已注册 | ✅ |
