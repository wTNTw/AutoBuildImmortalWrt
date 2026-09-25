---
title: 预置第三方 APK 必须匹配设备 apk 架构标签（aarch64_generic vs aarch64_cortex-a53）
tags: [build, apk, architecture, nikki, immutable-firmware, third-party-package]
module: rockchip/build25.sh
problem_type: build_failure
severity: P0
verified_on: 2026-09-25
verified_device: ImmortalWrt 25.12.1 r37978 / friendlyarm_nanopi-r5c (apk-tools 3.0.5)
---

# 症状

固件构建成功、刷入成功、Nikki 相关文件（`/usr/bin/mihomo`、`/usr/share/nikki-apk/*.apk`）都在，
但 **Nikki/LuCI-Nikki 始终没装上**。首启日志 `/overlay/log/boot-tuning.log`：

```
===== 安装预置 apk =====
ERROR: unable to select packages:
  nikki-2026.04.08-r1:
    error: uninstallable
    arch: aarch64_cortex-a53
    satisfies: world[nikki><Q1Vm3rpHIAclWiabhXK1jFUSwrfJ8=]
               luci-app-nikki-1.26.0-r1[nikki]
  结果: 0 个 nikki 相关包已安装
```

**误导性**：日志前半段还有 `wgetFailed to send request: Operation not permitted`、
`opening from cache https://istore.istoreos.com/... No such file`，
很容易被误判为「首启时网络没就绪」或「iStore 仓库索引拉取失败」。

# 根因分析

**架构标签不匹配**，与网络、依赖、版本冲突都无关。

设备侧（实测）：

```
root@ImmortalWrt:~# apk --print-arch
aarch64
root@ImmortalWrt:~# cat /etc/apk/arch
aarch64_generic
```

包侧：

```
root@ImmortalWrt:~# apk adbdump /usr/share/nikki-apk/nikki-2026.04.08-r1.apk
info:
  name: nikki
  version: 2026.04.08-r1
  arch: aarch64_cortex-a53      <-- 关键
  depends: # 11 items
    - ca-bundle / curl / firewall4 / ip-full / kmod-dummy / kmod-inet-diag
      kmod-nft-socket / kmod-nft-tproxy / kmod-tun / libc / yq
  provides: # 2 items
    - mihomo=2026.04.08-r1      <-- mihomo 由 nikki 自身提供，故「缺 mihomo 包」不成立
    - nikki-any
```

`arch` 不等于设备架构且不是 `noarch` 时，apk 直接判定 `uninstallable` 并拒绝安装（不进入依赖求解）。
`--allow-untrusted` 只关签名校验，**不解决架构问题**。

## 上游仓库的坑

`wukongdaily/apk` 同一功能提供两个 arm64 目录：

| 上游路径 | `arch` 标签 | 说明 |
|---|---|---|
| `run/arm64/nikki/` | `aarch64_generic` | ✅ 与本机型匹配（版本较旧） |
| `run/arm64-a53/nikki/` | `aarch64_cortex-a53` | ❌ 不匹配（版本较新） |

原脚本用 `find "$NK_SRC" -path '*nikki*' -name '*.apk'` 通配收集，**把两个架构的包都收进来**；
再叠加「同名包取最高版本」的去重策略，结果稳定选中 **版本更新但架构不兼容** 的 a53 变体，
于是每次构建都必现安装失败。

> 教训：`-path '*nikki*'` 这类单条件通配，无法表达「架构」这一维度；
> 而「取最高版本」在**跨架构**场景下等价于「取错误架构」。

# 解决方案

在收集阶段就把架构维度写进筛选条件（`rockchip/build25.sh`，commit `bd14e9d`）：

```sh
# 机型 apk 架构为 aarch64_generic，故只取上游 run/arm64/（generic 构建）；
# run/arm64-a53/ 的包标记为 aarch64_cortex-a53，架构不匹配会被 apk 直接判为
# uninstallable，导致首启安装失败（实测 2026-09-25，ImmortalWrt 25.12.1/rockchip）。
find "$NK_SRC" -path '*nikki*' -path '*/arm64/*' -name '*.apk' -exec cp -f {} "$NK_DST"/ \; 2>/dev/null
for r in $(find "$NK_SRC" -path '*nikki*' -path '*/arm64/*' -name '*.run' 2>/dev/null); do ... done

# 兜底：上游目录结构变化导致一个 generic 包都没取到时，回退为全部架构
if ! ls "$NK_DST"/*.apk >/dev/null 2>&1; then
    echo "  警告: 未取到 arm64(generic) 预置包，回退为全部架构"
    find "$NK_SRC" -path '*nikki*' -name '*.apk' -exec cp -f {} "$NK_DST"/ \; 2>/dev/null
fi
```

关键点：`-path '*/arm64/*'` 要求路径分段恰好是 `arm64`，
因此天然排除 `arm64-a53`（其分段是 `arm64-a53`），无需额外的负向条件。

# 验证

1. **构建期（可复现，不需真机）**：clone 上游后执行新筛选，只应得到 3 个 generic 包：
   `nikki-2026.03.10-r3.apk` / `luci-app-nikki-1.25.3-r1.apk` / `luci-i18n-nikki-zh-cn-26.088.44343~a20a48b.apk`。
2. **真机装前验证（无损）**：
   ```sh
   apk adbdump <file>.apk | grep -E 'name:|version:|arch:'   # 确认 arch: aarch64_generic
   apk add --simulate --allow-untrusted /usr/share/nikki-apk/*.apk
   # 期望：Installing nikki ... / luci-app-nikki ... / luci-i18n-nikki-zh-cn ... 3/3 无错
   ```
3. **首启后**：`apk list --installed | grep -i nikki` 应有 3 项。

# 预防策略

1. **预置第三方 APK 前，先比对 `apk --print-arch` / `cat /etc/apk/arch` 与包的 `adbdump arch` 字段**，
   这是唯一权威依据，别信文件名或目录名。
2. 收集条件必须**同时表达「功能名 + 架构」两个维度**，禁止只用功能名通配。
3. 跨架构的「同名取最高版本」是危险策略；去重必须在**同一架构内**进行。
4. 首次开机的自动安装务必**把结果写进日志并留存可读结论**（本项目 `boot-tuning.log` 的
   `结果: N 个 ... 已安装` 就是定位此问题的关键线索）。
5. 日志中出现 `wget: Operation not permitted` 时不要急于归因网络：先看 `unable to select packages`
   的具体子原因（`arch:` / `error: uninstallable` / 缺依赖）。
6. `--allow-untrusted` 仅解决签名，**不解决架构**；不要用它掩盖不可安装。

# 相关

- 同机另一个已修复的加载项缺陷：`files/etc/uci-defaults/98-docker-nftables-backend.sh`
  （LuCI「状态→nftables」误报 legacy iptables，根因是 dockerd 默认 iptables 后端写规则进 nft
  `table ip filter/nat`，被前端 `checkLegacyRules()` 误判；已切 `firewall-backend: nftables`）。
- 上游仓库：https://github.com/wukongdaily/apk （`run/arm64/` = generic，`run/arm64-a53/` = cortex-a53）
