# 支持的第三方软件列表如下 
 > 第三方软件就是ImmortalWrt仓库以外的软件包

 > **已弃用插件**：`luci-app-turboacc` 与 `luci-app-attendedsysupgrade` 已从本仓库移除。
 > 前者依赖 iptables 时代的 `kmod-ipt-offload`（官方源已无此包），其功能已由 `firewall` 原生的 `flow_offloading` 取代；
 > 后者依赖 ASU 在线升级服务，无法复现本仓库的自定义包组合。


| 第三方软件名称                  | 简介 / 功能描述                        | 来源 / 项目地址                                                                           |
| --------------------- | -------------------------------- | ----------------------------------------------------------------------------------- |
| luci-app-store        | iStore应用商店(0.1.30-1)             | [linkease/luci-app-store](https://github.com/linkease/istore)                 |
| luci-app-amlogic             | 晶晨宝盒(仅限ARM-64平台) | [ophub/luci-app-amlogic](https://github.com/ophub/luci-app-amlogic)                       |
| luci-app-adguardhome  | 本地 DNS 去广告解决方案                   | [AdGuardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)               |
| luci-app-advancedplus | 高级设置                   | [sirpdboy/luci-app-advancedplus](https://github.com/sirpdboy/luci-app-advancedplus)                                                                 |
| luci-app-netspeedtest | 网络测速插件-支持 Speedtest 测试           | [sirpdboy/luci-app-netspeedtest](https://github.com/sirpdboy/luci-app-netspeedtest)  |
| luci-app-netwizard    | 网络配置向导插件                          | [sirpdboy/luci-app-netwizard](https://github.com/sirpdboy/luci-app-netwizard)                                                                 |
| luci-app-partexp      | 分区扩容插件         | [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp)                             |
| luci-app-quickstart   | iStore首页和网络向导                  | [linkease/luci-app-quickstart](https://github.com/kiddin9/kwrt-packages/tree/main/luci-app-quickstart)                                                                 |
| luci-theme-kucat      | 酷猫主题                  | [sirpdboy/luci-theme-kucat](https://github.com/sirpdboy/luci-theme-kucat)                 |
| luci-app-oxidns       | OxiDNS 现代化高性能 DNS 分流与防污染工具   | [svenshi/luci-app-oxidns](https://oxidns.org/openwrt)                               |
| luci-app-nekobox               | 代理工具      | [Thaolga/luci-app-nekobox](https://github.com/Thaolga/openwrt-nekobox)       |
| luci-app-nikki                 | 代理工具               | [nikkinikki-org/nikki](https://github.com/nikkinikki-org/OpenWrt-momo)                                                                     |
| luci-app-momo                 | 代理工具               | [nikkinikki-org/momo](https://github.com/nikkinikki-org/OpenWrt-momo)                                                                     |
| tailscale             | ZeroTier 类似的 VPN 工具，基于 WireGuard | [tailscale/tailscale](https://github.com/tailscale/tailscale)                       |
| luci-app-lucky           | Lucky大吉,软硬路由公网神器,ipv6/ipv4 端口转发,反向代理 | [程序 gdy666/lucky](https://github.com/gdy666/lucky) [ipk仓库](https://dl.openwrt.ai/packages-24.10/aarch64_cortex-a53/kiddin9/)                      |
| luci-app-gecoosac           | 集客AC                | [lwb1978/openwrt-gecoosac](https://github.com/lwb1978/openwrt-gecoosac) |
| luci-app-taskplan             | 任务计划 |                        |
| luci-app-easytier             | 组网 | https://github.com/EasyTier/luci-app-easytier                       |
| luci-app-uninstall             | 高级卸载1.1.8 | [用于彻底卸载插件 点这里出处](https://www.bilibili.com/video/BV1dK1xBVEHF)                     |
| luci-theme-aurora      | 极光主题 0.9                 | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)                 |
| luci-app-bandix      | Bandix流量监控 0.11                 | [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix)                 |
| luci-app-rtp2httpd      |  IPTV 流媒体转发服务器                 | [stackia/rtp2httpd](https://github.com/stackia/rtp2httpd)                 |                    |
