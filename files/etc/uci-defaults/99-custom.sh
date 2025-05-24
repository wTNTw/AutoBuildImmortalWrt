#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
   。 "$SETTINGS_FILE"
fi

elif [ "$count" -gt 1 ]; then
    wan_ifname="eth1"
    lan_ifnames=""

    # 动态过滤除wan_ifname外的所有物理网卡
    for ifname in $ifnames; do
        if [ "$ifname" != "$wan_ifname" ]; then
            lan_ifnames="$lan_ifnames $ifname"
        fi
    done

    # 去除前导和后部空格
    lan_ifnames=$(echo "$lan_ifnames" | awk '{$1=$1}1')

    # 判断是否作为WAN口的接口确实存在
    if ! echo "$ifnames" | grep -qw "$wan_ifname"; then
        echo "错误：指定的WAN接口 $wan_ifname 不存在于系统中。" >> "$LOGFILE"
        exit 1
    fi

    # 配置wan接口
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'
    uci set network.wan.reqdhcp=1

    # 配置wan6接口（若需要）
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找LAN桥接设备对应的section
    section=$(uci show network | awk -F '[.=]' '/device\.$$/ && $0 ~ /^.*\.name='br-lan'$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "错误：未找到名称为br-lan的设备段。" >> "$LOGFILE"
        exit 1
    else
        # 删除原有ports列表
        uci -q delete "network.$section.ports"
        # 重新设置LAN桥接端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "LAN桥接端口已设置为：$lan_ifnames" >> "$LOGFILE"
    fi

    # 设置LAN接口为静态地址（根据设备需要）
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='192.168.100.1'
    uci set network.lan.netmask='255.255.255.0'
    echo "已将LAN口IP设置为 192.168.100.1 | 当前时间: $(date)" >> "$LOGFILE"

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0
