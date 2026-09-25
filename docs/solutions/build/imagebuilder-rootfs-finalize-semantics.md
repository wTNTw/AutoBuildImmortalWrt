---
title: ImageBuilder 收尾阶段的两个语义：自定义 files/ 覆盖包内同名文件、自动 enable 全部 init 服务
tags: [build, imagebuilder, rootfs, luci, menu, init-script, adguardhome, service-enable]
module: rockchip/build25.sh, files/usr/share/luci/menu.d/, files/etc/uci-defaults/99-custom.sh
problem_type: behavior_mismatch
severity: P2
verified_on: 2026-09-25
verified_device: ImmortalWrt 25.12.1 build #13 (run 36084723029) / friendlyarm_nanopi-r5c
---

# 结论速览

| 问题 | 结论 |
| --- | --- |
| `files/` 里的文件与包内文件同名时谁生效？ | **我们的 `files/` 生效**（自定义文件在包安装之后应用） |
| 新增一个含 `/etc/init.d/*` 的包，服务会自己跑起来吗？ | **rc.d 软链会被自动创建**，但**是否真正运行取决于包自身 init 脚本的 UCI 默认值** |

---

# 一、自定义 files/ 覆盖包内同名文件（用于改 LuCI 菜单归类）

## 症状 / 需求
需要把 `luci-app-irqbalance`、`luci-app-upnp` 的菜单项从「服务」改到「网络」。
这两个应用的菜单定义在包内 `usr/share/luci/menu.d/<app>.json`，键名即菜单路径
（`admin/services/irqbalance`）。

## 根因与做法
- LuCI 菜单以**路径为键**，因此不能「再加一个 `admin/network/xxx` 文件」——那会变成两个入口；
  必须用**同名文件**覆盖，把键改成 `admin/network/...`。
- ACL 授权按**应用名**（`rpcd/acl.d/<app>.json` 的 key），与菜单路径无关，故改路径**无需**改 ACL。
- `title` 必须保持与上游**完全一致**，否则 i18n（`luci-i18n-<app>-zh-cn`）的翻译会失配。

## 为什么覆盖一定生效（证据）
ImmortalWrt ImageBuilder 的 `target/imagebuilder/files/Makefile` 把 rootfs 收尾拆成两个目标：

```
package_install:   $(APK) add --arch ... $(BUILD_PACKAGES)     # 装包
prepare_rootfs:    $(call prepare_rootfs,$(TARGET_DIR),$(USER_FILES),...)   # 应用自定义文件
```

本次构建日志的**实际执行顺序**（run 36084723029）：

```
355  Installing packages...
756  Finalizing root filesystem...     <-- 这里应用 USER_FILES（cp -fpR，覆盖同名文件）
841  Building images...
```

`cp -fpR` 为覆盖语义，且发生在装包之后 → `files/usr/share/luci/menu.d/luci-app-upnp.json`
覆盖包内同名文件，`admin/services/upnp` 不再存在，不会产生重复菜单项。

## 预防
- 这类覆盖是「静态副本」，上游若**改动同名菜单文件的字段**（如新增 `depends`）或**重命名文件**，
  我们的副本会滞后（后者还会导致新旧入口并存）。升级 LuCI 版本后应重新比对上游 menu.d。
- 刷机后自查：`ls /usr/share/luci/menu.d/` 应只见 `admin/network/*` 路径的定义。
  ✅ **已实机确认（2026-09-25，r37978 / NanoPi R5C）**：两个 JSON 均为 `admin/network/*`，
  `grep -rl 'admin/services/\(upnp\|irqbalance\)'` 零命中；LuCI「网络」菜单下目视正常显示。

---

# 二、ImageBuilder 会自动 enable 全部 init 服务（但不等于会运行）

## 症状
构建日志 `Finalizing root filesystem...` 段出现 40 余条 `Enabling <svc>`，其中包含我们
**从未**手动 enable 的包：

```
Enabling adguardhome / irqbalance / miniupnpd / pbr / sqm / samba4 / dockerd / zram / oxidns ...
```

容易误判为「新增包会让服务默认跑起来」或「服务默认不启用」。

## 根因
- `prepare_rootfs` 会为镜像内**全部** `/etc/init.d/*` 创建 rc.d 软链，除非列在 `DISABLED_SERVICES`。
  → 因此 `99-custom.sh` 里那个「逐个 enable」的循环对已自动 enable 的服务是**冗余**的。
- 但 **rc.d 软链 ≠ 服务运行**：是否启动由包自身 init 脚本决定。
  AdGuardHome 的例子（`immortalwrt/packages/net/adguardhome/files/adguardhome.init`）：

  ```sh
  32  uci_validate_section 'adguardhome' 'adguardhome' "$config_name" \
  33      'enabled:bool:0' \            # <-- UCI 默认 enabled=0
  ...
  47  [ "$enabled" -eq "1" ] || return 1  # <-- 未启用则 start_service 直接空返回
  ```

  即：全新刷机（无 `/etc/config/adguardhome`，或 `enabled=0`）时，
  `start_service` 是空操作，**不会监听 53 端口，也不会与 dnsmasq 冲突**，
  仅在其 LuCI 页面被启用后才真正运行。

## 预防
- 新增含 init 脚本的包时：先看该 init 的 `enabled` 默认值与短路条件——
  默认 `enabled=1` 的服务会**开箱自动运行**，可能抢占端口（如 53/tcp+udp）；
  默认 `0` 的只是「已登记、待启用」。
- 需要「装了但不跑」时不必改 `99-custom.sh`，包自身的 UCI 默认值通常已经满足。

# 验证方法

```sh
# 1) 镜像内被自动 enable 的服务清单（构建日志）
grep -oE 'Enabling [a-z0-9_.-]+' build.log | sort -u

# 2) 装包/应用自定义文件/打镜像 的真实顺序
grep -nE 'Installing packages|Finalizing root filesystem|Building images' build.log

# 3) 包 init 脚本的默认值与短路条件
curl -sL https://raw.githubusercontent.com/immortalwrt/packages/openwrt-25.12/net/<pkg>/files/<pkg>.init \
  | grep -nE "enabled:bool|\\|\\| return"
```
