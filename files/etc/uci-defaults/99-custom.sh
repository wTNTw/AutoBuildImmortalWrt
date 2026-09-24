#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 因为本项目中 单网口模式是dhcp模式 直接就能上网并且访问web界面 避免新手每次都要修改/etc/config/network中的静态ip
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    . "$SETTINGS_FILE"
fi

# 1. 先获取所有物理接口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 根据板子型号映射WAN和LAN接口
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# 此处特殊处理个别开发板网口顺序问题
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *)
        # 默认第一个接口为WAN，其余为LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
esac

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

    # PPPoE设置
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    # 固定物理网卡 MAC 地址，防止像 NanoPi R5C 等无板载 EEPROM 的设备开机分配随机 MAC 导致漂移
    for iface in $ifnames; do
        if [ -d "/sys/class/net/$iface" ]; then
            cur_mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
            if [ -n "$cur_mac" ] && [ "$cur_mac" != "00:00:00:00:00:00" ]; then
                dev_sec=$(uci show network 2>/dev/null | grep "name='$iface'" | cut -d. -f2 | head -n1)
                if [ -z "$dev_sec" ]; then
                    uci add network device >/dev/null
                    dev_sec="@device[-1]"
                    uci set "network.$dev_sec.name=$iface"
                fi
                uci set "network.$dev_sec.macaddr=$cur_mac"
                echo "Persisted MAC for $iface: $cur_mac" >>$LOGFILE
            fi
        fi
    done

    uci commit network
fi

# 设置所有网口可访问网页终端
uci -q delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci -q set dropbear.@dropbear[0].Interface=''

# 4. 系统时区与国内高可靠 NTP 时间同步池 (防断电后证书与 DoH 校验失败)
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].timezone='CST-8'
uci -q delete system.ntp.server
uci -q add_list system.ntp.server='ntp.aliyun.com'
uci -q add_list system.ntp.server='ntp.tencent.com'
uci -q add_list system.ntp.server='time1.cloud.tencent.com'
uci -q add_list system.ntp.server='ntp.ntsc.ac.cn'
uci -q set system.ntp.enable_server='1'

# 5. 持久化系统滚动日志 (保留在 /overlay，限制 512KB 自动滚动轮转，防断网重启丢日志)
mkdir -p /overlay/log
uci -q set system.@system[0].log_type='file'
uci -q set system.@system[0].log_file='/overlay/log/syslog.log'
uci -q set system.@system[0].log_size='512'
uci -q set system.@system[0].log_rotate='4'
uci -q set system.@system[0].log_buffer_size='128'

# 6. 配置板载 LED 指示灯状态自适应 (仅对 Rockchip 开发板生效，按实际 sysfs 动态绑定)
case "$board_name" in
    *nanopi*|*radxa*|*rockchip*|*fastrhino*|*orangepi*|*t68m*)
        # 先清理固件自带的 LED 定义，避免同一 LED 被重复绑定产生告警
        for idx in $(uci show system 2>/dev/null | grep "=led" | cut -d. -f2 | cut -d= -f1 | sort -rn); do
            uci -q delete "system.$idx"
        done

        led_sec=0
        for want in lan wan wlan; do
            real=""
            for d in /sys/class/leds/*; do
                [ -d "$d" ] || continue
                base=$(basename "$d")
                case "$base" in
                    *":$want"|*":$want-"*|*"led-$want"*|*"-$want"*)
                        real="$base"
                        break
                        ;;
                esac
            done
            [ -z "$real" ] && continue

            led_sec=$((led_sec + 1))
            sec="led_custom_$led_sec"
            uci -q set "system.$sec=led"
            uci -q set "system.$sec.name=$(echo "$want" | tr 'a-z' 'A-Z')"
            uci -q set "system.$sec.sysfs=$real"

            case "$want" in
                lan|wan)
                    if [ "$want" = "lan" ]; then
                        dev_name=$(echo "$lan_ifnames" | awk '{print $1}')
                    else
                        dev_name=$(echo "$wan_ifname" | awk '{print $1}')
                    fi
                    if [ -n "$dev_name" ] && [ -d "/sys/class/net/$dev_name" ]; then
                        uci -q set "system.$sec.trigger='netdev'"
                        uci -q set "system.$sec.dev=$dev_name"
                        uci -q set "system.$sec.mode='link tx rx'"
                    else
                        uci -q set "system.$sec.trigger='defaulton'"
                    fi
                    ;;
                wlan)
                    if [ -d /sys/class/ieee80211 ]; then
                        uci -q set "system.$sec.trigger='phy0tpt'"
                    else
                        uci -q set "system.$sec.trigger='defaulton'"
                    fi
                    ;;
            esac
        done
        ;;
esac

uci commit system
uci commit dropbear
uci commit ttyd

# 7. 开启 NAT 流量分载 (software flow offloading)
# firewall4 已依赖 kmod-nft-offload，无需额外安装；已建立的 NAT 连接将走 nftables flowtable 快速路径。
# 注意：硬件分载在 RK3568 上无意义，保持关闭；另若日后启用 SQM 整形，需关闭此项（分载会绕过整形队列）。
if uci -q get firewall.@defaults[0] >/dev/null 2>&1; then
    uci -q set firewall.@defaults[0].flow_offloading='1'
    uci -q set firewall.@defaults[0].flow_offloading_hw='0'
    uci commit firewall
fi

# 8. zram 内存压缩交换：作为 OOM 兜底，全程在内存中压缩，不写 eMMC
uci -q set system.@system[0].zram_size_mb='1024'
uci -q set system.@system[0].zram_comp_algo='lzo'
uci commit system

# 9. 监控数据持久化：nlbwmon / vnstat 默认落在 /var （tmpfs），重启即丢，改到 /overlay
mkdir -p /overlay/nlbwmon /overlay/vnstat 2>/dev/null
if [ -f /etc/config/nlbwmon ]; then
    uci -q set nlbwmon.@nlbwmon[0].database_directory='/overlay/nlbwmon'
    uci -q set nlbwmon.@nlbwmon[0].commit_interval='10m'
    uci commit nlbwmon
fi
if [ -f /etc/vnstat.conf ]; then
    # vnstat 默认数据库目录可能被注释掉，这里同时处理注释与未注释两种形式
    sed -i 's#^[[:space:]]*;\?[[:space:]]*DatabaseDir.*#DatabaseDir "/overlay/vnstat"#' /etc/vnstat.conf
    grep -q '^DatabaseDir' /etc/vnstat.conf || echo 'DatabaseDir "/overlay/vnstat"' >> /etc/vnstat.conf
fi
if [ -f /etc/config/vnstat ]; then
    uci -q delete vnstat.@vnstat[0].interface
    for i in $wan_ifname $lan_ifnames; do
        dev=$(echo "$i" | awk '{print $1}')
        [ -n "$dev" ] && [ -d "/sys/class/net/$dev" ] && uci -q add_list "vnstat.@vnstat[0].interface=$dev"
    done
    uci commit vnstat
fi

# 10. 服务开机启动策略
# 直接可用的监控/优化服务：启用
for svc in irqbalance zram nlbwmon vnstat netdata miniupnpd; do
    if [ -x "/etc/init.d/$svc" ]; then
        "/etc/init.d/$svc" enable 2>/dev/null
    fi
done

# 需要用户先完成配置的服务：保持禁用，避免单网卡/单线环境下产生意外行为
# - mwan3  : 需先添加并启用第二条 WAN（wanb），否则会接管默认路由
# - usteer / dawn : 单射频环境下无漫游对象，且 dawn 默认启用 kicking 可能主动踢开客户端
for svc in mwan3 usteer dawn; do
    if [ -x "/etc/init.d/$svc" ]; then
        "/etc/init.d/$svc" disable 2>/dev/null
    fi
done

# 11. eMMC 定期 TRIM：每周日凌晨 4 点对全部支持 discard 的文件系统执行 fstrim
if [ -x /usr/sbin/fstrim ]; then
    CRON=/etc/crontabs/root
    [ -f "$CRON" ] || touch "$CRON"
    if ! grep -q 'fstrim' "$CRON" 2>/dev/null; then
        echo '0 4 * * 0 /usr/sbin/fstrim -a >/dev/null 2>&1' >> "$CRON"
    fi
    /etc/init.d/cron enable 2>/dev/null
fi

# 12. DNS 缓存调优
# 解析链保持原有逻辑：由 dnsmasq 作为唯一解析器，上游继续使用运营商 / 上级设备
# 通过 /tmp/resolv.conf.d/resolv.conf.auto 下发的 DNS，不接入 oxidns / AdGuardHome。
if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
    # 缓存调优：默认 cachesize=150、min_cache_ttl=0，对家庭/办公规模明显偏小
    uci -q set dhcp.@dnsmasq[0].cachesize='10000'
    uci -q set dhcp.@dnsmasq[0].min_cache_ttl='120'

    # 只服务内网客户端，不对外提供递归解析
    uci -q set dhcp.@dnsmasq[0].localservice='1'

    # 上游恢复为 resolv.conf.auto（运营商 / 上级设备下发）。
    # 仅移除早期版本写入的固定公共 DNS，用户自行添加的其他条目保持不动。
    uci -q set dhcp.@dnsmasq[0].noresolv='0'
    for s in 223.5.5.5 223.6.6.6 119.29.29.29 180.76.76.76; do
        uci -q del_list "dhcp.@dnsmasq[0].server=$s"
    done

    uci commit dhcp
fi

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
    echo "fix ttyd show msg: /usb/bin/zsh: not found" >>$LOGFILE
fi

# 只有安装了 luci-app-quickfile 才执行
if [ -f /usr/bin/quickfile ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null

    uci add nginx server
    uci rename nginx.@server[-1]='_lan'

    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'

    uci commit nginx
    echo "fix quickfile nginx config" >>$LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall

# 追加新的 zone + forwarding 配置
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 检查并配置 Wi-Fi 无线网络 (针对板载 MT7921 等无线网卡自动启用)
if command -v wifi >/dev/null 2>&1; then
    # 若 /etc/config/wireless 不存在或为空，主动触发一次探测生成
    if [ ! -s /etc/config/wireless ]; then
        wifi config
    fi

    radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
    if [ -n "$radios" ]; then
        echo "Configuring wireless interfaces: $radios" >>$LOGFILE
        for r in $radios; do
            uci set "wireless.$r.disabled=0"
            uci set "wireless.$r.country=CN"
        done

        # 为第一个无线网络配置默认 AP
        first_radio=$(echo "$radios" | head -n1)
        if_sec="default_$first_radio"
        if ! uci get "wireless.$if_sec" >/dev/null 2>&1; then
            if_sec=$(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1 | head -n1)
        fi

        if [ -n "$if_sec" ]; then
            uci set "wireless.$if_sec.ssid=ImmortalWrt-WiFi"
            uci set "wireless.$if_sec.encryption=psk2"
            uci set "wireless.$if_sec.key=12345678"
            uci set "wireless.$if_sec.network=lan"
            echo "Wireless AP enabled: SSID=ImmortalWrt-WiFi" >>$LOGFILE
        fi

        uci commit wireless
    else
        echo "No wireless radio detected during uci-defaults." >>$LOGFILE
    fi
fi

# 自动配置社区第三方预编译软件包源 (涵盖 kenzok8 / passwall / 各种社区常用插件)
if [ -f /etc/opkg.conf ]; then
    # 注释 check_signature，避免第三方无签名源在更新时报错
    sed -i 's/^option check_signature/# option check_signature/' /etc/opkg.conf
fi

if [ -d /etc/opkg ]; then
    CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
    opkg_arch=$(opkg print-architecture 2>/dev/null | awk 'NR>1 {print $2}' | tail -n 1)
    [ -z "$opkg_arch" ] && opkg_arch="aarch64_generic"

    case "$opkg_arch" in
        *x86_64*)
            cat << 'EOF' > "$CUSTOMFEEDS"
src/gz community_kiddin9 https://dl.openwrt.ai/packages-24.10/x86_64/kiddin9
EOF
            ;;
        *aarch64*|*arm64*|*cortex-a53*)
            cat << 'EOF' > "$CUSTOMFEEDS"
src/gz community_kiddin9 https://dl.openwrt.ai/packages-24.10/aarch64_generic/kiddin9
src/gz community_cortex_a53 https://dl.openwrt.ai/packages-24.10/aarch64_cortex-a53/kiddin9
EOF
            ;;
        *)
            cat << EOF > "$CUSTOMFEEDS"
src/gz community_kiddin9 https://dl.openwrt.ai/packages-24.10/${opkg_arch}/kiddin9
EOF
            ;;
    esac
    echo "Community customfeeds configured for architecture: $opkg_arch" >> $LOGFILE
fi

# 优化软中断多核负载均衡 (RPS/XPS)，分摊双 2.5G 网卡与无线数据包至所有 CPU 核心
cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
if [ "$cpu_count" -ge 4 ]; then
    mask="f"
elif [ "$cpu_count" -ge 2 ]; then
    mask="3"
else
    mask="1"
fi

for iface in /sys/class/net/*; do
    [ -d "$iface/queues" ] || continue
    for rx in "$iface"/queues/rx-*; do
        [ -f "$rx/rps_cpus" ] && echo "$mask" > "$rx/rps_cpus" 2>/dev/null
    done
    for tx in "$iface"/queues/tx-*; do
        [ -f "$tx/xps_cpus" ] && echo "$mask" > "$tx/xps_cpus" 2>/dev/null
    done
done

# 将需要在每次开机重新施加的内核/挂载调优固化到独立脚本，并由 /etc/rc.local 调用
cat << 'EOF' > /etc/boot-tuning.sh
#!/bin/sh
# 自动生成：开机内核与 I/O 调优

# 1) RPS/XPS：将网卡收发包软中断分摊到所有 CPU 核心
cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
if [ "$cpu_count" -ge 4 ]; then
    mask="f"
elif [ "$cpu_count" -ge 2 ]; then
    mask="3"
else
    mask="1"
fi
for rx in /sys/class/net/*/queues/rx-*/rps_cpus; do
    [ -f "$rx" ] && echo "$mask" > "$rx" 2>/dev/null
done
for tx in /sys/class/net/*/queues/tx-*/xps_cpus; do
    [ -f "$tx" ] && echo "$mask" > "$tx" 2>/dev/null
done

# 2) 根文件系统以 noatime 重新挂载，减少 eMMC 上无意义的访问时间写入
if ! awk '$2 == "/" { exit !(index($4, "noatime") > 0) }' /proc/mounts 2>/dev/null; then
    mount -o remount,noatime / 2>/dev/null
fi

# 3) CPU 调频：优先使用 schedutil（响应更快），不可用时保持系统默认
governor_file=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
avail_file=/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
if [ -f "$governor_file" ] && [ -f "$avail_file" ]; then
    if grep -qw schedutil "$avail_file"; then
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$gov" ] && echo schedutil > "$gov" 2>/dev/null
        done
    fi
fi

exit 0
EOF
chmod +x /etc/boot-tuning.sh

# 移除早期版本生成的 rps-tuning.sh，避免两套脚本重复
sed -i '/rps-tuning.sh/d' /etc/rc.local 2>/dev/null
rm -f /etc/rps-tuning.sh 2>/dev/null

if [ -f /etc/rc.local ]; then
    if ! grep -q "boot-tuning.sh" /etc/rc.local; then
        if grep -q "^exit 0" /etc/rc.local; then
            sed -i 's#^exit 0#[ -x /etc/boot-tuning.sh ] \&\& /etc/boot-tuning.sh\nexit 0#' /etc/rc.local
        else
            echo "[ -x /etc/boot-tuning.sh ] && /etc/boot-tuning.sh" >> /etc/rc.local
        fi
    fi
fi

# 去除后台无效报错提示
# 1) 清理 LuCI 编译缓存，避免首次进入后台出现旧菜单/未定义模块告警
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache/* 2>/dev/null

# 2) 确保 uci-defaults 日志文件权限正确，避免后续追加写入报错
[ -f "$LOGFILE" ] && chmod 644 "$LOGFILE" 2>/dev/null

# 3) 修正部分插件（advancedplus / 其他）对缺失 zsh 的调用引起的终端刷屏报错
for f in /etc/init.d/advancedplus /etc/profile; do
    [ -f "$f" ] && sed -i '/zsh/d' "$f" 2>/dev/null
done

# 4) 屏蔽 opkg 对第三方无签名源的告警输出
if [ -f /etc/opkg.conf ] && ! grep -q 'option check_signature' /etc/opkg.conf; then
    echo '# option check_signature' >> /etc/opkg.conf
fi

exit 0
