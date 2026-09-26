---
title: 第三方插件 apk 的预置交付：资产格式、首启安装时机与 ucitrack 注册顺序
tags: [build, apk, third-party-package, imagebuilder, ucitrack, uci-defaults, netwizard, partexp]
module: rockchip/build25.sh, files/etc/uci-defaults/99-custom.sh
problem_type: integration_delivery
severity: P2
verified_on: 2026-09-26
verified_device: ImmortalWrt 25.12.1 r37978 / friendlyarm_nanopi-r5c (apk-tools 3.0.5, kernel 6.12.94)
---

# 背景：为什么第三方插件不能在构建期安装

25.12 起改用 apk。ImageBuilder 的本地 `packages/` 目录**只能经 `packages.adb` 索引**被 apk 看到，
而该索引在本镜像里生成不了（`mkndx` 失败，且错误被 `|| true` 与输出重定向掩盖）；
即使生成了索引，镜像构建器的 apk 调用也不带 `--allow-untrusted`，未签名的第三方包仍会被拒。

但**设备端**的 `apk add --allow-untrusted <本地 .apk 文件>` 是可用的（已在真机验证）。
因此本项目对第三方插件的统一交付方式是：

```
构建期：把 .apk 预置进固件（files/usr/share/<plugin>-apk/，随 FILES= 进 rootfs）
   ↓
首次开机：/etc/boot-tuning.sh（由 99-custom.sh 生成，由 rc.local 在 S95done 调用）
        执行 `apk add --allow-untrusted --no-network <预置目录>/*.apk`
   ↓
装包时：apk 执行包自带的 postinst → default_postinst（详见坑 3）
```

这样包会被 apk **正常登记**（可 `apk del` / 升级），优于 OxiDNS 那种「解包铺文件」的文件注入方式。

> 用 `--no-network` 先试、失败再退回联网安装，是为了让依赖齐备时的安装完全离线；
> 依赖是否齐备直接决定这条路径成不成立，见坑 4。

# 坑 1：同一个 release 提供两套资产，包格式不同

sirpdboy 系列插件的 release 同时发布 10 个架构 × 2 套 SDK 分支的资产，**两套的包格式不一样**：

| 资产 | 内部格式 | 用途 |
|---|---|---|
| `SNAPSHOT-<arch>.tar.gz` | **`.apk`** | apk-tools 3.x（25.12），本项目**只取这条** |
| `openwrt-24.10-<arch>.tar.gz` | **`.ipk`** | opkg（24.10），本项目不取 |

```console
$ tar -tzvf SNAPSHOT-aarch64_generic.tar.gz
drwxr-xr-x  packages_ci/
-rw-r--r--  packages_ci/luci-app-netwizard-2.1.5-r20260312.apk                      17478
-rw-r--r--  packages_ci/luci-i18n-netwizard-zh-cn-26.060.49879~201cb64.apk           3297

$ tar -tzvf openwrt-24.10-aarch64_generic.tar.gz
drwxr-xr-x  packages_ci/
-rw-r--r--  packages_ci/luci-app-netwizard_2.1.5-r20260312_all.ipk                  17621
```

**别用文件名里的架构去判断兼容性**：这类插件多为 `PKGARCH:=all`（装入后标 `noarch`），
同一分支下 10 个架构资产的 apk **字节数完全相同**（实测 netwizard 的 aarch64_generic 与 x86_64
均为 17478 字节）。仍按 `DISTRIB_ARCH`（`aarch64_generic`）取，只是为了与设备对齐、避免日后再踩。

判定方法（不需要真机）：

```sh
tar -tzvf <asset>.tar.gz            # 看内部是 .apk 还是 .ipk
```

注意 `.apk` 不是 tar 包（v3 是 `ADB` 容器 + raw deflate，`41 44 42 64` 开头），
`tar -tzf` 打不开它；但 tar.gz 里的**外层**资产用 `tar -tzvf` 就能看清内部文件名与后缀。

# 坑 2：装了但不生效 —— ucitrack(S80) 早于 rc.local(S95done)

**症状**：插件文件都到位、LuCI 菜单也能看到，但向导页的「保存并应用」没有任何效果，
必须**再重启一次**才好用。

**根因**是两件事叠加：

1. `ucitrack` 的 `register_init()` 要求 init **已经 enabled**，否则直接跳过、不注册触发器：

   ```sh
   # /etc/init.d/ucitrack
   register_init() {
       local config="$1"; local init="$2"; shift; shift
       if [ -x "$init" ] && "$init" enabled && ! grep -sqE 'USE_PROCD=.' "$init"; then
           logger -t "ucitrack" "Setting up /etc/config/$config reload trigger for non-procd $init"
           procd_add_config_trigger "config.change" "$config" "$init" "$@"
       fi
   }
   ```

   而这些包**不含任何会调用 `enable` 的 postinst**（netwizard 自带的 uci-defaults 只做了
   `chmod +x /etc/init.d/netwizard`；partexp 根本没有 init 脚本）。首启安装发生在镜像已成形
   之后，`/etc/rc.d/S99<svc>` 并不存在，于是 `"$init" enabled` 为假 → 触发器不注册。

2. 现代 `ucitrack` 只在**开机时**由 `service_triggers()` 扫描 `/usr/share/ucitrack/*.json`
   （START=80），而首启安装发生在 rc.local（S95done），**这一轮开机不会再扫第二次**。

**修复**（`files/etc/uci-defaults/99-custom.sh`，在 `apk add` 之后补两步）：

```sh
/etc/init.d/netwizard enable       # 建出 /etc/rc.d/S99netwizard
/etc/init.d/ucitrack reload        # 让 service_triggers() 重跑一遍
```

`ucitrack` 既没定义 `start_service` 也没定义 `reload_service`，所以 `reload` 会回落到 `start`，
走的就是开机 S80 的同一条 `rc_procd start_service` 路径（`/lib/functions.sh` 的
`_procd_close_service` 会调用 `service_triggers`）。因此效果与「该包在构建期就在镜像里」等价。

**顺带发现**：netwizard 自带的 `/etc/uci-defaults/40-luci-netwizard` 里那段
`uci add ucitrack netwizard / set init=netwizard / commit ucitrack` 在这套固件上是**遗留空操作**——
现代 ucitrack 不再读 `/etc/config/ucitrack`（该文件在本机根本不存在，`uci show ucitrack` 报
`Entry not found`），真正生效的只有包内 `/usr/share/ucitrack/*.json` + procd。所以不能指望
「包自带的 uci-defaults 会把注册做掉」。

开机不动作的正确判断方式（避免误判为「首启会改配置」）：

```sh
# /etc/init.d/netwizard
boot()  { XBOOT=1; start; }
start() { check_lock && exit 0
          [ "x$XBOOT" = "x1" ] && exit 0     # 开机路径在此直接返回
          ... configure_network ... }        # 只有手动 start 才会执行
```

# 坑 3：包自带的 uci-defaults 由 `default_postinst` 执行，可能承担关键一步

`apk add` 时 apk 会执行包的 postinst（`. /lib/functions.sh; default_postinst`），
而 `default_postinst` 会用**本包的 file list** 匹配并 source 包自带的 `/etc/uci-defaults/`：

```sh
# /lib/functions.sh
	if [ -z "$root" ]; then
		...
		if grep -m1 -q -s "^/etc/uci-defaults/" "$filelist"; then
			[ -d /tmp/.uci ] || mkdir -p /tmp/.uci
			for i in $(grep -s "^/etc/uci-defaults/" "$filelist"); do
				( [ -f "$i" ] && cd "$(dirname $i)" && . "$i" ) && rm -f "$i"
			done
			uci commit
		fi
	fi
```

（按 file list 匹配意味着**只执行本包自己的** uci-defaults，不会顺带跑别的包的。）

**这不是可选的**：`luci-app-partexp` ship 的 `/usr/bin/partexp` 与 `/usr/libexec/rpcd/partexp`
权限是 `0644`，全靠它自带的 `zzz_luci-app-partexp` 补 `+x` 并 `rpcd restart`：

```sh
#!/bin/sh
chmod +x /usr/bin/partexp /usr/libexec/rpcd/partexp
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache
exit 0
```

**真机实证**（该包已装在同版本设备上）：

```console
$ ls -la /usr/bin/partexp /usr/libexec/rpcd/partexp
-rwxr-xr-x  27992  /usr/bin/partexp
-rwxr-xr-x   8043  /usr/libexec/rpcd/partexp
$ ubus -v list partexp
'partexp' @716bf93d
	"autopart":{...}  "get_log":{...}  "get_devices":{...}
	"get_status":{...}  "save_config":{...}
```

若这段 uci-defaults 没跑到，表现是「包装上了，但 ubus 对象不出现」——排查时先看这两个文件的权限位。

# 坑 4：运行时依赖必须进 PACKAGES，且包名要核到具体 feed

第三方插件包声明的依赖，**构建期不会自动被解析**（构建期根本没装这个包）。
若依赖不在镜像里，首启的 `apk add --no-network` 会失败并退化成联网安装——对刚刷完机、
还没配好上网的设备并不可靠。所以声明依赖要显式写进 `rockchip/build25.sh` 的 `PACKAGES`。

两个具体注意点：

1. **内核模块必须走构建期安装**，才能与内核版本严格匹配（与 Nikki 的 `kmod-*` 同理）。
2. **包名要核对到具体 feed**，写错包名会让 `make image` 直接失败。同一个源目录下不一定都有：

   | 包 | 实际所在 feed |
   |---|---|
   | `fdisk` / `blkid` / `losetup` | `packages/aarch64_generic/base/`（util-linux 子包） |
   | `resize2fs` | `packages/aarch64_generic/base/`（e2fsprogs 子包，但**是独立包名**） |
   | `f2fs-tools` | `packages/aarch64_generic/base/` |
   | `bc` / `parted` / `btrfs-progs` | `packages/aarch64_generic/packages/` |
   | `block-mount` | `targets/rockchip/armv8/packages/` |
   | `kmod-loop` | `targets/rockchip/armv8/kmods/<kernel-ver-hash>/` |

   注意 `fdisk`/`blkid`/`losetup`/`resize2fs` **不在** `packages/` feed 里，只在 `base/` 里；
   只看一个 feed 的目录列表会得出「包不存在」的错误结论。

# 验证方法

**构建期（可复现，不需真机）** —— 把该段连同开关变量抽出来、把 `NW_DST`/`PE_DST` 指向临时目录后执行，
应真实下载并收集到预期的包：

```sh
{ echo 'ENABLE_NETWIZARD=1; ENABLE_PARTEXP=1'
  sed -n '/^# ============ 第三方插件预置 apk/,/^# 构建镜像/p' rockchip/build25.sh
} | tr -d '\r' | sed 's#/home/build/immortalwrt/files#/tmp/pptest#' | bash
```

```console
---- netwizard 预置的 apk 清单 ----
-rw-r--r--  17478  luci-app-netwizard-2.1.5-r20260312.apk
-rw-r--r--   3297  luci-i18n-netwizard-zh-cn-26.060.49879~201cb64.apk
---- partexp 预置的 apk 清单 ----
-rw-r--r--  15740  luci-app-partexp-2.0.5-r20260318.apk
-rw-r--r--   2281  luci-i18n-partexp-zh-cn-25.355.34625~38e15b6.apk
```

同时建议对改动过的脚本做 LF 归一化后跑 `bash -n` 与 `dash -n`（工作区 checkout 是 CRLF，
直接对工作区文件跑 `dash -n` 会因 `\r` 报 `word unexpected (expecting "do")` 这类假错误）；
`99-custom.sh` 里生成 `/etc/boot-tuning.sh` 的那段在单引号 heredoc 内，**主文件的语法检查覆盖不到它**，
需要把 heredoc 体单独抽出来再检查一次。

**设备侧（只读，无损）**：

```sh
# 1) 包是否装上了
apk list --installed | grep -E '^luci-(app|i18n)-(netwizard|partexp)-'

# 2) 是否需要 enable（有 init 脚本的插件）
/etc/init.d/<svc> enabled && echo yes || echo no

# 3) ucitrack 触发器是否注册成功（看开机日志里有没有这一行）
logread | grep -i ucitrack | grep -i <svc>
# 期望：Setting up /etc/config/<cfg> reload trigger for non-procd /etc/init.d/<svc>

# 4) rpcd/ubus 对象是否可用（partexp 这类）
ubus -v list partexp

# 5) 安装日志（首启结果会写在这里）
grep -A5 -E '安装预置 (netwizard|partexp) apk' /overlay/log/boot-tuning.log
```

# 预防策略

1. **取资产时先 `tar -tzvf` 看内部后缀**，确认是 `.apk` 还是 `.ipk`；不要凭文件名里的架构判断兼容性。
2. **新增插件先查它有没有 `/etc/init.d/*` 与 `/etc/uci-defaults/*`**，据此决定要不要补 `enable` + `ucitrack reload`：
   - 有 init 脚本、且需要「改配置后自动重启」→ **必须**补这两步（坑 2）；
   - 只有 uci-defaults（如 partexp）→ 装包时会自动执行，不用补（坑 3）。
3. **插件的声明依赖逐条落到 `PACKAGES`**，并到 `base/` `packages/` `targets-*/` 三个 feed 里分别核对包名（坑 4）。
4. **预置流程要有「取不到包就告警」的兜底**：首启安装失败只会安静地记一行日志跳过，
   不主动检查会刷出「以为装了、其实没装」的固件。本项目用 `require_preset_apk()` 承担这件事。
5. **插件获取逻辑收敛成共用函数**（`preset_plugin_apks` / `require_preset_apk`），
   避免每个插件各写一份、日后改目录约定或上游资产命名时漏改。
6. 交付方式的选择优先级：**官方 apk 源可解析 → 进 `PACKAGES`**；
   否则 **预置 apk + 首启安装**（可被包管理器登记）；最后才是**文件注入**（OxiDNS，不可卸载/升级）。

# 相关

- 同为「预置第三方 apk」的架构问题（包 `arch` 必须等于设备 apk 架构）：
  `docs/solutions/build/third-party-apk-arch-mismatch.md`
- ImageBuilder 收尾阶段的覆盖语义与「自动 enable 全部 init 服务」：
  `docs/solutions/build/imagebuilder-rootfs-finalize-semantics.md`
- 代码落点：`rockchip/build25.sh`（`preset_plugin_apks` / `require_preset_apk`，`ENABLE_NETWIZARD` / `ENABLE_PARTEXP`）、
  `files/etc/uci-defaults/99-custom.sh`（`/etc/boot-tuning.sh` 的第 6/7/8 项）
