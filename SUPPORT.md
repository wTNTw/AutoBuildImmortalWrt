# 本仓库支持的机型

> **本仓库已精简**：仅保留唯一工作流 `.github/workflows/build-rockchip-25.12.x.yml`（平台 Rockchip / Luci 25.12.x）。
> 其余平台工作流（x86-64、QEMU-arm64、树莓派、全志 sunxi、Flippy/armsr-armv8、斐讯 N1、
> 晶晨电视盒子、MediaTek 无线路由器、ipq807x、MT7621）与 ISO 安装器工作流均已移除。

## 本机型（工作流默认 profile）

| 型号 | 厂商 | 处理器 | profile | Luci 版本 |
| --- | --- | --- | --- | --- |
| NanoPi R5C | FriendlyARM | RK3568（4×Cortex-A55） | `friendlyarm_nanopi-r5c` | 25.12.x |

## 工作流支持的 profile 全量列表（共 62 个）

> 与工作流 `profile` 选项逐项一致（由工作流文件导出；改动工作流时需同步刷新本列表）。

```
linkease_easepi-r1
9tripod_x3568-v4
ariaboard_photonicat
ariaboard_photonicat2
armsom_sige3
armsom_sige7
cyber_cyber3588-aib
ezpro_mrkaio-m68s
firefly_roc-rk3328-cc
firefly_roc-rk3568-pc
friendlyarm_nanopc-t4
friendlyarm_nanopc-t6
friendlyarm_nanopi-r2c
friendlyarm_nanopi-r2c-plus
friendlyarm_nanopi-r2s
friendlyarm_nanopi-r3s
friendlyarm_nanopi-r4s
friendlyarm_nanopi-r4se
friendlyarm_nanopi-r4s-enterprise
friendlyarm_nanopi-r5c
friendlyarm_nanopi-r5s
friendlyarm_nanopi-r6c
friendlyarm_nanopi-r6s
friendlyarm_nanopi-r76s
huake_guangmiao-g4c
lunzn_fastrhino-r66s
lunzn_fastrhino-r68s
lyt_t68m
mmbox_anas3035
nlnet_xiguapi-v3
pine64_rock64
pine64_rockpro64
radxa_cm3_io
radxa_e20c
radxa_e25
radxa_e52c
radxa_rock-2a
radxa_rock-2f
radxa_rock-3a
radxa_rock-3b
radxa_rock-3c
radxa_rock-4c-plus
radxa_rock-4d
radxa_rock-4se
radxa_rock-5a
radxa_rock-5b
radxa_rock-5b-plus
radxa_rock-5-itx
radxa_rock-5c
radxa_rock-5t
radxa_rock-pi-4a
radxa_rock-pi-e
radxa_rock-pi-s
radxa_zero-3e
radxa_zero-3w
sinovoip_bpi-r2-pro
widora_mangopi-m28c
widora_mangopi-m28k
xunlong_orangepi-5
xunlong_orangepi-5-plus
xunlong_orangepi-r1-plus
xunlong_orangepi-r1-plus-lts
```

## 说明

- 软件包空间（`rootfs_partsize`）、Docker（`include_docker`）、iStore（`enable_store`）、PPPoE（`enable_pppoe`）均为工作流入参，详见工作流文件内注释。
- 本仓库仅覆盖 Rockchip 平台；如需确认某机型的具体 SoC，以 ImmortalWrt 上游 `target/linux/rockchip` 的目标定义为准。
