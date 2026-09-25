---
title: RPS 掩码在开机流程结束后被改回（XPS 不受影响）—— 定位与分层兜底方案
tags: [tuning, rps, xps, smp-affinity, rtl8125, hotplug, boot-tuning, rockchip]
module: files/usr/sbin/custom-rps-apply, files/etc/hotplug.d/net/99-custom-tuning, files/etc/hotplug.d/iface/99-custom-tuning, files/etc/uci-defaults/99-custom.sh
problem_type: runtime_tuning
severity: P3
verified_on: 2026-09-25
verified_device: FriendlyARM NanoPi R5C / ImmortalWrt 25.12.1（kernel 6.12.94，r37978）
---

# 症状

开机后 `/sys/class/net/eth*/queues/rx-*/rps_cpus` 是 **1**（eth0）和 **4**（eth1），
而同一脚本写入的 XPS 却正常保留为 `f`：

```text
/sys/class/net/eth0/queues/rx-0/rps_cpus = 1     ← 期望 f
/sys/class/net/eth0/queues/rx-1/rps_cpus = 1     ← 期望 f
/sys/class/net/eth0/queues/tx-0/xps_cpus = f     ← 正常
/sys/class/net/eth1/queues/rx-0/rps_cpus = 4     ← 期望 f
```

同一段代码先写 rps 再写 xps，结果 xps 生效而 rps 不生效，说明不是"没执行"，而是**执行之后又被改写**。

# 已排除的原因（逐条有证据）

| 假设 | 证伪方式 | 结论 |
| --- | --- | --- |
| 我们的脚本没跑 | XPS 是 f，说明同一段代码执行成功（两者共用 `$iface` 与 `$mask`） | 排除 |
| 系统自带 `40-net-smp-affinity` 覆盖 | 它写的是 `/proc/irq/*/smp_affinity`，**不写 rps_cpus**；且本机 RTL8125 多队列 IRQ 名为 `eth0-0…eth0-31`，它按 `"eth0$"` 匹配不到，实际报 `/proc/irq//smp_affinity: nonexistent directory`，**整体失效** | 排除 |
| 有周期性回滚 | 手动 `echo f > rps_cpus` 后观察 90 秒，值稳定不变 | 排除"周期" |
| irqbalance 接管 RPS | `strings /usr/sbin/irqbalance \| grep -i rps` 无任何命中；`--help` 也无 RPS 相关选项 | 排除 |
| 其它用户态脚本 | 全盘搜索写 `rps_cpus` 的脚本，只有本项目自己的 `/etc/hotplug.d/net/99-custom-tuning` | 排除 |

# 结论

改写发生在**开机期间的某个时刻**（S95done 之后），改写者不在用户态脚本里（怀疑在内核/驱动侧
的队列初始化或链路状态变化路径）。由于无法用纯用户态手段阻止它，方案改为**不追究单一触发点，
而是让我们的值始终是最后写入的一方**。

# 方案：分层施加（单一实现 + 多个时机）

把掩码算法收敛到一个共用脚本，避免多处实现导致"不同时机写入不同值"：

| 时机 | 落点 |
| --- | --- |
| 首启（uci-defaults） | `99-custom.sh` 内联调用 |
| 开机（rc.local / S95done） | `boot-tuning.sh` 步骤 1 与步骤 5 调用 |
| **开机后 20s / 60s** | `boot-tuning.sh` 步骤 5 后台延迟补施（覆盖 S95done 之后的改写） |
| 网卡出现（net add） | `/etc/hotplug.d/net/99-custom-tuning` |
| 接口 up（ifup/ifupdate） | `/etc/hotplug.d/iface/99-custom-tuning` |

共用脚本：`/usr/sbin/custom-rps-apply`，两种调用方式：

```sh
sh /usr/sbin/custom-rps-apply          # 全部网卡
sh /usr/sbin/custom-rps-apply eth0     # 指定网卡
```

# 关键实现细节

1. **用 `sh <文件>` 调用，不依赖可执行位**。`files/` 里的脚本在镜像中不保证保留执行权限
   （现有 `/etc/hotplug.d` 下脚本都是 644），显式用 `sh` 解释可以规避这个不确定性。
2. **`hotplug-call` 是 source 执行**（`. $script`），所以热插拔脚本本身不需要可执行位；
   文件名用 `99-` 前缀保证在 `40-net-smp-affinity` 等之后执行。
3. **事件与变量来源不同**：`net` 事件导出 `DEVICENAME`/`INTERFACE`；`iface` 事件导出
   `INTERFACE`（逻辑名）与 `DEVICE`（物理名）。施加 RPS 需要物理设备名，因此分别取
   `DEVICENAME` 与 `DEVICE`。
4. **自证机制**：延迟补施结束后把各队列的 rps/xps 实际值写入
   `/overlay/log/boot-tuning.log`，刷机后可直接核对，无需额外实验。

# 刷机后如何确认

```sh
grep -A 20 'RPS/XPS 延迟补施结果' /overlay/log/boot-tuning.log
# 期望：eth0/eth1 的 rx-* 与 tx-* 全部为 f
for f in /sys/class/net/eth*/queues/rx-*/rps_cpus; do echo "$f = $(cat $f)"; done
```

# 注意事项

- RPS 属于**次要**优化：本机 RTL8125 驱动的队列 IRQ 本身已分散在 4 个 CPU 上
  （`/proc/irq/*/smp_affinity` 可见 1/2/4/8 分布），因此 RPS 未生效对吞吐的影响有限，
  优先级低于 sysctl / offload 等项。
- 这套方案是"最后写入者胜"，如果将来某个组件持续周期性地改写 RPS，需要改为
  "值不一致时才纠正"的看门狗，而不是继续增加施加点。
