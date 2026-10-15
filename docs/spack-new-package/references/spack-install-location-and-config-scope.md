# Spack 1.x 安装位置、config scope 语义与安装脚本空间检查

覆盖实测陷阱：
1. 安装根目录配置键 `install_root` **失效**（真正的键是 `install_tree: root:`）
2. `spack config get --scope=X` 只读该 scope，**不是**合并后的生效配置
3. 包自带安装脚本（如 HPCKit 的 `install.sh`）用 `df` 做空间检查（两种失败模式，机制已实测确认，见第 3 节）
4. install tree 更换后 spack DB 残留死记录 → `spack find` 多条 / `spack location -i` 歧义（第 4 节）
5. 幂等工作流脚本重写 config.yaml 导致安装树视图回退：备份→跑→恢复（第 5 节）
附：Spack 1.x 编译器注册落盘位置 = user scope packages.yaml（第 6 节）；tmpfs 安装树易失性（第 7 节）

---

## 1. `install_root` 是死键：真正的安装树根是 `install_tree: root:`

### 现象（实测）

`config.yaml` 里写：

```yaml
config:
  install_root: $spack/var/opt
```

`spack install` 却把包装到 `$spack/opt/spack/linux-aarch64/<pkg>-<ver>-<hash>/`，
`$spack/var/opt` 始终为空，而且 spack **不报任何错**（未知键被静默忽略）。

### 根因

Spack 1.x 的配置键是 `config:install_tree:root:`（默认 `$spack/opt/spack`），
不存在 `install_root`。旧键被当作未知键丢弃。

### 诊断

```bash
source $spack/share/spack/setup-env.sh
spack config blame config | grep -iE "install_tree|install_root"
# install_tree 会带来源标注（defaults / 你的 config.yaml）；install_root 不会出现
spack location -i <已安装包>     # 看实际前缀落在 opt/spack 还是 var/opt
```

**排查任何"配置写了但没生效"问题的首选命令就是 `spack config blame <section>`** ——
它逐项标出该值来自哪个 scope，比猜是哪层配置在起作用快得多。

### 正确写法

```yaml
config:
  install_tree:
    root: /mnt/kp-spack/opt
```

或者**完全不改配置**，直接把有空闲的文件系统挂到当前安装树根上（见第 3 节方案 ①）。

### 附：`$spack/opt/spack/` 里有什么（判断能否在其上覆盖挂载）

```
$spack/opt/spack/
├── sbang              # spack 的脚本 shebang 包装器（可重建）
├── .spack-db/         # 安装数据库索引 + lock（可重建）
└── linux-aarch64/     # 实际安装前缀
```

只有 `sbang` + `.spack-db/` + 空的 `<arch>/` 时，在其上覆盖挂载是安全的
（spack 会重建 DB）。

---

## 2. `spack config get --scope=<scope>` 只读该 scope

`spack config --scope=site get packages` 只输出 **site scope**（`$spack/etc/spack/site/`）
里显式写的键，**不包含**：

- `$spack/etc/spack/*.yaml`（工作流/脚本自己写的那一层）
- `~/.spack/packages.yaml`（user scope）
- builtin 默认值

后果：**"导出的配置副本"几乎为空**。实测某 stage1 工作流用
`spack config --scope=site get compilers > compilers.yaml` 导出的
`compilers.yaml` / `repos.yaml` 是空文件，`packages.yaml` 只剩 site scope 那几行 ——
看起来像"配置没写进去"，实际是**命令取错了范围**。

### 正确用法

```bash
spack config get packages      # 去掉 --scope → 合并后的最终生效值
spack config blame packages    # 逐项标出来自哪个 scope（查"谁覆盖了谁"）
```

### 教训

配置文件"内容是空的/不完整"时，先怀疑**读取范围**，再怀疑写入失败。
写出去的那一层（`$SPACK_ETC/packages.yaml`）和读进来的 scope 可能不是同一个目录 ——
两个同名 `packages.yaml` 会同时被合并，容易误判。

---

## 3. 包自带 install.sh 的 `df` 空间检查：ext4 保留块让 Avail 恒为 0

### 现象

HPCKit 的 `install.sh` 自带空间检查，直接拒绝安装：

```
The space of the HPCKit installation directory is insufficient.
About 10 GB space is required for installing HPCKit.
```

但目标文件系统实际上还有几十 G 未被使用。

### 根因：ext4 保留块（默认 5%）

**`df` 的 Avail 已经扣掉了给 root 的保留块：**

```
Avail = (f_bfree - Reserved block count) × block size
```

实测 `/dev/mapper/openeuler-home`（ext4，803.8 G）：

| 量 | 值 |
|----|-----|
| `f_bfree`（真实空闲） | ≈ 26.3 G |
| Reserved block count | 10,717,286 × 4 K = **43.9 G** |
| ⇒ df Avail | **0**（26.3 < 43.9） |

保留块池 > 真实空闲时，**Avail 恒为 0，root 也一样显示 0**。而安装器解析的是
`df -k <install_dir>` 的可用量，于是**必被拒** —— 即使真实空闲 26 G 远大于它要求的 10 G，
即使以 root 运行。

### 诊断命令

```bash
# 1. df 与真实空闲的差异
df -h <目标目录>
tune2fs -l <设备> | grep -iE "block count|reserved block count|block size"
#   用 Block count / Reserved block count / Block size 手算真实空闲

# 2. 安装脚本到底怎么检查的（关键：它检查哪个路径）
grep -nE "df |avail|Avail|space" <stage>/install.sh

# 3. 确认是否还有别的空闲空间可用
findmnt -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL
vgs; lvs                     # LVM 是否还能扩
```

### 解除方式（按推荐度）

**① 把有空闲的文件系统挂到安装树根上 —— 无需改任何配置或脚本（首选）**

安装器检查的是 `<install_dir>` **所在文件系统**的 `df` 结果。只要让安装树根落在
有空闲的文件系统上，检查自然通过：

```bash
# spack 的安装树根 = $spack/opt/spack（见第 1 节）
mkdir -p <spack>/opt/spack
mount /dev/nvme0n1p1 <spack>/opt/spack        # 真磁盘：可 umount + wipefs -a 还原
# 或不落盘：
mount -t tmpfs -o size=200G tmpfs <spack>/opt/spack
```

**为什么优于改配置：** `install_root` 本来就不生效（第 1 节），挂载法同时绕开了
"配置键到底叫什么/会不会被脚本重写"的问题 —— 脚本每次运行都会重写 `config.yaml`，
手工 sed 改的安装根会被覆盖掉。

**② 释放目标文件系统空间**（删旧的重复安装实例、可重下载的源码缓存等）。

**③ `tune2fs -m 1 <dev>` 缩小保留块池** —— 能让 `df` 立刻显示空闲，但会削掉共享
文件系统留给 root 的应急余量（40 G → 8 G），**多用户共享节点上不推荐**。

### ✅ 检查机制实测确认（后续部署会话，HPCKit 26.1.RC1）

- `software_size` 读自 `$current_dir/script/bootstrapper.conf` 的 `software_size=10485760`
  （单位 **KB**，= 10 GB），读取方式 `grep "$var" "$file" | awk -F= '{print $2}'`
- 唯一调用点：`install_dir_space_check ${selected_install_path}`，其中
  `selected_install_path` 就是命令行 `--prefix` 的值（先 `${path%*/}` 剥尾斜杠）
  —— **确认检查的就是 --prefix 路径**，不是父目录也不是 `$HOME`
- 比较逻辑：`avail_size=$(df -k <prefix> | sed -n '2p' | awk -F " " '{print $(NF-2)}')`，
  `if [ $software_size -gt $avail_size ]; then exit 1`
- **触发条件 = avail < software_size，不只有 Avail=0 一种**：只要 prefix 所在文件系统
  的 df 可用量小于 10 GB 就拒绝（保留块吞掉 Avail 只是其中一种成因）

一行复现/诊断：

```bash
size=$(grep software_size <stage>/script/bootstrapper.conf | awk -F= '{print $2}')
avail=$(df -k <install_prefix> 2>/dev/null | sed -n '2p' | awk '{print $(NF-2)}')
[ "$size" -gt "$avail" ] 2>/dev/null && echo FAIL || echo "PASS (avail=${avail}KB)"
```

本次解除方式：install_tree 根落在有空闲的文件系统（/tmp tmpfs，458G 空闲）后安装
一次通过（源码走缓存，秒级完成）。tmpfs 的易失性代价见第 7 节。

### 附：多用户共享节点的判断依据

`/home` 的 `df` Avail 在**动手之前就已经是 0**，且系统上有多个其他用户的进程在跑。
这类"目标盘天生满"的情况不是自己操作造成的，**不要靠删别人的东西解决** ——
优先找空闲块设备（`lsblk`、`blkid`、`wipefs -n` 只读探测确认无分区表/无文件系统/未挂载/未占用），
把决策交回用户。

---

## 4. install tree 更换后 DB 残留死记录：`spack find` 多条 → `spack location -i` 歧义

### 现象

`spack find -lv hpckit` 列出多条记录，其中多数前缀目录已不存在；`spack location -i hpckit` 报：

```
==> Error: hpckit matches multiple packages.
```

脚本里裸写 `spack location -i hpckit` 会拿到空串 + 非零退出（实测它让 setup 脚本的
编译器注册步骤误报"未找到 hpckit 安装路径，请先安装 hpckit"）。

### 根因

install tree 换过根（换文件系统/换目录）或目录被手工清理后，`.spack-db/index.json`
的记录**不会自动失效** —— spack 只查 DB、不查前缀存在性。旧视图残留记录与当前有效
记录同时可见，形成歧义。

### 诊断

```bash
spack find -l | grep -vE '^==|^--' | while read h name rest; do
  p=$(spack location -i /$h 2>/dev/null)
  [ -n "$p" ] && [ ! -d "$p" ] && echo "STALE: $h $name $rest"
done
```

（或直接审计 `.spack-db/index.json`：字段在 `database.installs` 下，比对 `spec.name`
与 `path` 的 `isdir`。）

### 清理

```bash
# 普通 uninstall 会因 "There are still dependents" 拒绝（依赖方也是死记录时照样拒）；
# --force 只删 DB 记录、不碰磁盘 —— 前缀目录本来就不存在，无文件可删
spack uninstall -y --force /hash1 /hash2 ...
```

清理后 `spack location -i <pkg>` 恢复唯一解析。

### 附：symlink 前缀的判别

install tree 里的包目录可能是指向另一份 spack 实例的**符号链接**（物理包在持久盘）：

```bash
ls -ld <prefix>      # lrwxrwxrwx → 链接；真目录显示 drwx
du -sh <prefix>      # 链接只显示 4.0K —— 但这不等于空包
<prefix>/.../bin/gcc --version   # 直接验证关键二进制
```

`du` 显示 0/4.0K ≠ 安装损坏：先 `ls -ld` 看是否链接，再跑关键二进制，再下结论。

---

## 5. 幂等工作流脚本重写 config.yaml → 安装树视图回退

### 现象

setup 脚本每次运行都用**模板**重写 `$SPACK_ETC/config.yaml`。若模板写的是死键
`install_root:`（第 1 节），重写后 `install_tree` 回落默认 `$spack/opt/spack` ——
当前生效 install_tree 指向别处（tmpfs/自定义盘）时，**整个已装包视图瞬间消失**：

- 下游阶段看不到装在另一棵树里的包（hdf5/netcdf/cmake 等）
- 旧视图 DB 若还有第 4 节的死记录 → `spack location -i` 歧义回归
- 典型症状：报告同时出现 `HPCKit 状态 | 已安装` 与 `HPCKit 安装路径 | 未安装`
  （find 有记录、location 歧义拿不到前缀）

### 工作法：备份 → 跑脚本 → 恢复

```bash
cp $SPACK_ETC/config.yaml /tmp/config.yaml.bak
bash setup_spack.sh                            # 脚本正常跑完、报告刷新
cp /tmp/config.yaml.bak $SPACK_ETC/config.yaml
spack find -l | grep -E 'hdf5|netcdf'          # 验证下游关键包视图未丢
```

一次性修法：把脚本模板里的 `install_root:` 行改成 `install_tree: { root: <实际树> }`，
让模板与现状一致，重跑不再回退。

---

## 6. 附：Spack 1.x 编译器注册落盘位置

`spack compiler find --scope=site <bin目录>` 在 Spack 1.x **不写** `compilers.yaml`
（site 的 compilers.yaml 保持为空/不存在）；编译器作为 external 包记录在 user scope
`~/.spack/packages.yaml` 的 `gcc:` / `llvm:` 条目：

```yaml
gcc:
  externals:
  - spec: gcc@12.3.1 languages:='c,c++,fortran'
    prefix: /opt/HPCKit/25.1.0/compiler/gcc
    extra_attributes:
      compilers:
        c: /opt/HPCKit/25.1.0/compiler/gcc/bin/gcc
```

验证：`spack compiler list`；`spack config blame packages | grep -E '(gcc|llvm):'`。
两个注意点：

- 条目已存在且前缀有效时 `compiler find` 报 `Found no new compilers` —— **不是失败**，
  是无需重复注册
- external 前缀可能指向**已删除的旧目录**（记录在、二进制没了）：`compiler list`
  仍显示该版本，但 `%gcc`/`%llvm` 构建会失败 —— 与第 4 节死记录同源，
  换新 HPCKit 前缀后需核对路径存在性并重注册

---

## 7. 附：tmpfs 安装树的易失性（第 3 节方案 ① 的代价）

install tree 落在 tmpfs（或直接指向 /tmp）：**重启后 tmpfs 清空，其中"真目录"形态的
包全部丢失（DB 一起丢）**。实测一例：hpckit/hmpi 物理包恰在另一持久 spack 实例目录、
经 symlink 接入（幸存）；同期编译的 hdf5/netcdf 等是 tmpfs 真目录 —— 重启即需重装。

持久化做法：物理载荷放真磁盘、包目录 symlink 进 tmpfs install tree；或重启后重跑
批量安装脚本。交付/交接时必须写明这一风险。
