# Stage3.5 → Stage3 回传清单

> 由 manual_build.sh 自动生成。
> 以下包在 stage3.5 中手动编译成功，编译命令已提取，需 stage3 据此编写 package.py。

| 包名 | 编译器 | 版本 | 编译命令 | 安装路径 | 构建脚本 |
|------|--------|------|---------|---------|---------|
| elmerfem | bisheng | 9.0 | cmake -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_Fortran_COMPILER=flang -DCMAKE_INSTALL_PREFIX=<prefix> -DCMAKE_BUILD_TYPE=Release -DWITH_ElmerIce=ON -DWITH_CONTRIB=ON -DBLAS_LIBRARIES=<openblas>/lib/libopenblas.so -DLAPACK_LIBRARIES=<openblas>/lib/libopenblas.so -DCMAKE_C_FLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int" -DCMAKE_Fortran_FLAGS="-ffree-line-length-none" -DWITH_ELMERGUI:BOOL=FALSE -DWITH_MPI=ON -DWITH_OpenMP=ON -DWITH_Mumps=OFF -DWITH_Hypre=OFF -DWITH_Trilinos=OFF -DWITH_LUA=OFF -DWITH_Zoltan=OFF -DMPI_C_COMPILER=mpicc -DMPI_Fortran_COMPILER=mpif90 && make -j$(nproc) && make install | /home/zhangyuhang/workflow/spack-workflow/manual-build/elmerfem/install | /home/zhangyuhang/workflow/spack-workflow/manual-build/elmerfem/build.sh |
