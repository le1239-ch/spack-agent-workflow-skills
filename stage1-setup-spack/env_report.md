# 环境基线报告 (env_report.md)

> 本文件由 setup_spack.sh 自动生成，请勿手动编辑。
> 后续所有阶段引用此文件中的路径和版本信息。

| 项目 | 值 |
|------|-----|
| 架构 | aarch64 |
| CPU 型号 | Kunpeng 920 72F8 |
| 总核数 | 608 |
| NUMA 节点数 | 32 |
| Socket 数 | 2 |

## CPU 详细信息

```
Architecture:                       aarch64
CPU op-mode(s):                     64-bit
Byte Order:                         Little Endian
CPU(s):                             608
On-line CPU(s) list:                0-607
Vendor ID:                          HiSilicon
BIOS Vendor ID:                     HiSilicon
BIOS Model name:                    Kunpeng 920 72F8
Model:                              0
Thread(s) per core:                 1
Core(s) per socket:                 304
Socket(s):                          2
Stepping:                           0x0
Frequency boost:                    disabled
CPU max MHz:                        2000.0000
CPU min MHz:                        1200.0000
BogoMIPS:                           200.00
Flags:                              fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve asimdfhm dit uscat ilrcpc flagm ssbs sb dcpodp sve2 sveaes svepmull svebitperm svesha3 svesm4 flagm2 frint svei8mm svebf16 i8mm bf16 dgh ecv afp rpres sme smef64f64 smei8i32 smef16f32 smeb16f32 smef32f32 smefa64 wfxt
L1d cache:                          19 MiB (608 instances)
L1i cache:                          19 MiB (608 instances)
L2 cache:                           456 MiB (608 instances)
NUMA node(s):                       32
NUMA node0 CPU(s):                  0-37
NUMA node1 CPU(s):                  38-75
NUMA node2 CPU(s):                  76-113
NUMA node3 CPU(s):                  114-151
NUMA node4 CPU(s):                  152-189
NUMA node5 CPU(s):                  190-227
NUMA node6 CPU(s):                  228-265
NUMA node7 CPU(s):                  266-303
```
| 操作系统 | openEuler 22.03 (LTS-SP4) |

## OS 详细信息

```
NAME="openEuler"
VERSION="22.03 (LTS-SP4)"
ID="openEuler"
VERSION_ID="22.03"
PRETTY_NAME="openEuler 22.03 (LTS-SP4)"
ANSI_COLOR="0;31"

```
| Spack 版本 | 1.2.1 |
| Spack 架构 | linux-openeuler22-aarch64 |
| Spack 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1 |
| Spack 配置目录 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/etc/spack |
| 由工作流安装 | false |

## Spack 已加载包

```
```
| kp-spack repo 路径 | /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof |

## 鲲鹏 repo 中的可用包

```
boost_opt
bwa_opt
cufflinks_opt
eigen_opt
hdf5_opt
hmpi
hpckit
htslib_opt
kalign
kallisto_opt
kpblas
kpfft
kpfftw
kpkml
kpksvml
kpkupl
kplapack
kpscalapack
kpscasolver
kpsolver
kpspblas
kpvml
lammps_opt
nwchem_opt
py_hatch_docstring_description
py_legacy_api_wrap
py_numpy
py_scanpy
py_scipy
samtools_opt
siesta_opt
vasp
xdrfile
zstd
```
| 鲲鹏 repo 挂载验证 | ✅ spack info hpckit 成功 |
| HPCKit 状态 | 已安装 |
| HPCKit 安装路径 | /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/opt/spack/linux-aarch64/hpckit-26.0.RC1-tkllhlr |
| 编译器注册 | ✅ gcc + bisheng 已注册（落盘 /home/zhangyuhang/workflow/spack-workflow/user-config/packages.yaml） |
| BiSheng 路径 | /opt/HPCKit/26.0.RC1/compiler/bisheng |
| BiSheng 版本 | BiSheng Enterprise 5.1.0.2 clang version 19.1.7 (f38ff5c4a507) |
| HPCKit 环境路径 | /opt/HPCKit/26.0.RC1 |
| GCC 版本 | gcc (gcc for openEuler 3.0.3) 12.3.1 |
| HMPI mpicc | gcc -I/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/include -I/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/include/openmpi -I/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/include/openmpi/opal/mca/hwloc/hwloc201/hwloc/include -I/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/include/openmpi/opal/mca/event/libevent2022/libevent -I/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/include/openmpi/opal/mca/event/libevent2022/libevent/include -L/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/lib -Wl,-rpath -Wl,/opt/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi/lib -Wl,--enable-new-dtags -lmpi |
| spec 解析验证 | ✅ 全部成功 |

## NUMA 拓扑

```
available: 32 nodes (0-31)
node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37
node 0 size: 63632 MB
node 0 free: 52906 MB
node 1 cpus: 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75
node 1 size: 64466 MB
node 1 free: 62294 MB
node 2 cpus: 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113
node 2 size: 64506 MB
node 2 free: 63394 MB
node 3 cpus: 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151
node 3 size: 64506 MB
node 3 free: 63723 MB
node 4 cpus: 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189
node 4 size: 64506 MB
node 4 free: 61891 MB
node 5 cpus: 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227
node 5 size: 64506 MB
node 5 free: 62584 MB
node 6 cpus: 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265
node 6 size: 64506 MB
node 6 free: 63323 MB
node 7 cpus: 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303
node 7 size: 64506 MB
node 7 free: 63592 MB
node 8 cpus: 304 305 306 307 308 309 310 311 312 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 329 330 331 332 333 334 335 336 337 338 339 340 341
node 8 size: 64506 MB
node 8 free: 53895 MB
node 9 cpus: 342 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 377 378 379
node 9 size: 64506 MB
node 9 free: 57290 MB
node 10 cpus: 380 381 382 383 384 385 386 387 388 389 390 391 392 393 394 395 396 397 398 399 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417
node 10 size: 64506 MB
node 10 free: 46653 MB
node 11 cpus: 418 419 420 421 422 423 424 425 426 427 428 429 430 431 432 433 434 435 436 437 438 439 440 441 442 443 444 445 446 447 448 449 450 451 452 453 454 455
node 11 size: 64506 MB
node 11 free: 61023 MB
node 12 cpus: 456 457 458 459 460 461 462 463 464 465 466 467 468 469 470 471 472 473 474 475 476 477 478 479 480 481 482 483 484 485 486 487 488 489 490 491 492 493
node 12 size: 64506 MB
node 12 free: 58401 MB
node 13 cpus: 494 495 496 497 498 499 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 516 517 518 519 520 521 522 523 524 525 526 527 528 529 530 531
node 13 size: 64506 MB
node 13 free: 56921 MB
node 14 cpus: 532 533 534 535 536 537 538 539 540 541 542 543 544 545 546 547 548 549 550 551 552 553 554 555 556 557 558 559 560 561 562 563 564 565 566 567 568 569
node 14 size: 64506 MB
node 14 free: 58746 MB
node 15 cpus: 570 571 572 573 574 575 576 577 578 579 580 581 582 583 584 585 586 587 588 589 590 591 592 593 594 595 596 597 598 599 600 601 602 603 604 605 606 607
node 15 size: 63461 MB
node 15 free: 51425 MB
node 16 cpus:
node 16 size: 0 MB
node 16 free: 0 MB
node 17 cpus:
node 17 size: 0 MB
node 17 free: 0 MB
node 18 cpus:
node 18 size: 0 MB
node 18 free: 0 MB
node 19 cpus:
node 19 size: 0 MB
node 19 free: 0 MB
node 20 cpus:
node 20 size: 0 MB
node 20 free: 0 MB
node 21 cpus:
node 21 size: 0 MB
node 21 free: 0 MB
node 22 cpus:
node 22 size: 0 MB
node 22 free: 0 MB
node 23 cpus:
node 23 size: 0 MB
node 23 free: 0 MB
node 24 cpus:
node 24 size: 0 MB
node 24 free: 0 MB
node 25 cpus:
node 25 size: 0 MB
node 25 free: 0 MB
node 26 cpus:
node 26 size: 0 MB
node 26 free: 0 MB
node 27 cpus:
node 27 size: 0 MB
node 27 free: 0 MB
node 28 cpus:
node 28 size: 0 MB
node 28 free: 0 MB
node 29 cpus:
node 29 size: 0 MB
node 29 free: 0 MB
node 30 cpus:
node 30 size: 0 MB
node 30 free: 0 MB
node 31 cpus:
node 31 size: 0 MB
node 31 free: 0 MB
node distances:
node   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31 
  0:  10  20  20  20  30  30  30  30  40  40  40  40  40  40  40  40  61  71  71  71  81  81  81  81  91  91  91  91  91  91  91  91 
  1:  20  10  20  20  30  30  30  30  40  40  40  40  40  40  40  40  71  61  71  71  81  81  81  81  91  91  91  91  91  91  91  91 
  2:  20  20  10  20  30  30  30  30  40  40  40  40  40  40  40  40  71  71  61  71  81  81  81  81  91  91  91  91  91  91  91  91 
  3:  20  20  20  10  30  30  30  30  40  40  40  40  40  40  40  40  71  71  71  61  81  81  81  81  91  91  91  91  91  91  91  91 
  4:  30  30  30  30  10  20  20  20  40  40  40  40  40  40  40  40  81  81  81  81  61  71  71  71  91  91  91  91  91  91  91  91 
  5:  30  30  30  30  20  10  20  20  40  40  40  40  40  40  40  40  81  81  81  81  71  61  71  71  91  91  91  91  91  91  91  91 
  6:  30  30  30  30  20  20  10  20  40  40  40  40  40  40  40  40  81  81  81  81  71  71  61  71  91  91  91  91  91  91  91  91 
  7:  30  30  30  30  20  20  20  10  40  40  40  40  40  40  40  40  81  81  81  81  71  71  71  61  91  91  91  91  91  91  91  91 
  8:  40  40  40  40  40  40  40  40  10  20  20  20  30  30  30  30  91  91  91  91  91  91  91  91  61  71  71  71  81  81  81  81 
  9:  40  40  40  40  40  40  40  40  20  10  20  20  30  30  30  30  91  91  91  91  91  91  91  91  71  61  71  71  81  81  81  81 
 10:  40  40  40  40  40  40  40  40  20  20  10  20  30  30  30  30  91  91  91  91  91  91  91  91  71  71  61  71  81  81  81  81 
 11:  40  40  40  40  40  40  40  40  20  20  20  10  30  30  30  30  91  91  91  91  91  91  91  91  71  71  71  61  81  81  81  81 
 12:  40  40  40  40  40  40  40  40  30  30  30  30  10  20  20  20  91  91  91  91  91  91  91  91  81  81  81  81  61  71  71  71 
 13:  40  40  40  40  40  40  40  40  30  30  30  30  20  10  20  20  91  91  91  91  91  91  91  91  81  81  81  81  71  61  71  71 
 14:  40  40  40  40  40  40  40  40  30  30  30  30  20  20  10  20  91  91  91  91  91  91  91  91  81  81  81  81  71  71  61  71 
 15:  40  40  40  40  40  40  40  40  30  30  30  30  20  20  20  10  91  91  91  91  91  91  91  91  81  81  81  81  71  71  71  61 
 16:  61  71  71  71  81  81  81  81  91  91  91  91  91  91  91  91  10  255  255  255  255  255  255  255  255  255  255  255  255  255  255  255 
 17:  71  61  71  71  81  81  81  81  91  91  91  91  91  91  91  91  255  10  255  255  255  255  255  255  255  255  255  255  255  255  255  255 
 18:  71  71  61  71  81  81  81  81  91  91  91  91  91  91  91  91  255  255  10  255  255  255  255  255  255  255  255  255  255  255  255  255 
 19:  71  71  71  61  81  81  81  81  91  91  91  91  91  91  91  91  255  255  255  10  255  255  255  255  255  255  255  255  255  255  255  255 
 20:  81  81  81  81  61  71  71  71  91  91  91  91  91  91  91  91  255  255  255  255  10  255  255  255  255  255  255  255  255  255  255  255 
 21:  81  81  81  81  71  61  71  71  91  91  91  91  91  91  91  91  255  255  255  255  255  10  255  255  255  255  255  255  255  255  255  255 
 22:  81  81  81  81  71  71  61  71  91  91  91  91  91  91  91  91  255  255  255  255  255  255  10  255  255  255  255  255  255  255  255  255 
 23:  81  81  81  81  71  71  71  61  91  91  91  91  91  91  91  91  255  255  255  255  255  255  255  10  255  255  255  255  255  255  255  255 
 24:  91  91  91  91  91  91  91  91  61  71  71  71  81  81  81  81  255  255  255  255  255  255  255  255  10  255  255  255  255  255  255  255 
 25:  91  91  91  91  91  91  91  91  71  61  71  71  81  81  81  81  255  255  255  255  255  255  255  255  255  10  255  255  255  255  255  255 
 26:  91  91  91  91  91  91  91  91  71  71  61  71  81  81  81  81  255  255  255  255  255  255  255  255  255  255  10  255  255  255  255  255 
 27:  91  91  91  91  91  91  91  91  71  71  71  61  81  81  81  81  255  255  255  255  255  255  255  255  255  255  255  10  255  255  255  255 
 28:  91  91  91  91  91  91  91  91  81  81  81  81  61  71  71  71  255  255  255  255  255  255  255  255  255  255  255  255  10  255  255  255 
 29:  91  91  91  91  91  91  91  91  81  81  81  81  71  61  71  71  255  255  255  255  255  255  255  255  255  255  255  255  255  10  255  255 
 30:  91  91  91  91  91  91  91  91  81  81  81  81  71  71  61  71  255  255  255  255  255  255  255  255  255  255  255  255  255  255  10  255 
 31:  91  91  91  91  91  91  91  91  81  81  81  81  71  71  71  61  255  255  255  255  255  255  255  255  255  255  255  255  255  255  255  10 
```

| kqmalloc | /usr/local/ksl/lib/libkqmalloc.so |

## Spack 配置来源

```
compilers concretizer definitions env_vars include view develop mirrors repos packages modules config upstreams bootstrap ci cdash toolchains
```

## 当前 repos.yaml

```
repos:
  - /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof
```

## 当前 packages.yaml

```
packages:
  all:
    target: [aarch64]
    providers:
      blas: [kpblas]
      lapack: [kplapack]
      mpi: [hmpi]
  hpckit:
    require: "@26.0.RC1"
```

## 通过条件检查

| 条件 | 状态 |
|------|------|
| target=aarch64 | ✅ |
| Spack 可用 | ✅ |
| kp-spack repo 已挂载 | ✅ |
| spack info hpckit 成功 | ✅ |
| HPCKit 已安装 | ✅ |
| 编译器已注册 | ✅ |
| spec 解析成功 | ✅ |
