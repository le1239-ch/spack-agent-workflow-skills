# 手动编译日志 (manual_build_log.md)

> 由 manual_build.sh 自动维护。
> 记录每个包的手动编译过程和结果。

| 包名 | 编译器 | 版本 | 状态 | 重试次数 | 编译命令摘要 | 备注 |
|------|--------|------|------|---------|------------|------|
| elmerfem | bisheng | 9.0 | ✅ 成功 | 1 | cmake + make -j$(nproc) + make install，使用 bisheng flang/clang 编译器，openblas-clang 版本，ElmerIce netcdf 功能因 CMake FindNetCDF 未识别自定义变量而自动禁用（避免了 .mod 不兼容问题） | spack 安装失败因 netcdf-fortran 被 gcc 构建但 elmerfem 用 flang，.mod 不兼容；手动编译不指定 netcdf 路径，CMake 自动禁用 netcdf 相关功能 |
