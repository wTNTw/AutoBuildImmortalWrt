#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方APK软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/apk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 拷贝 run/arm64 下所有 run 文件和apk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  # 解压并拷贝apk到packages目录
  sh shell/apk-prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories信息——————"
cat repositories
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn docker"
    echo "Adding package: luci-i18n-dockerman-zh-cn docker"
fi
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# 硬件驱动与无线网络支持 (针对 NanoPi R5C 等设备强化 2.5G 网卡与 MT7921 Wi-Fi 6)
PACKAGES="$PACKAGES kmod-r8125"
PACKAGES="$PACKAGES kmod-mt7921-common kmod-mt7921-firmware kmod-mt7921e"
PACKAGES="$PACKAGES iw iwinfo wpad-openssl"
PACKAGES="$PACKAGES kmod-btusb mt7921bt-firmware"

# 存储与文件系统支持 (USB 自动挂载，NTFS/ext4/exFAT 原生驱动，磁盘维护工具)
PACKAGES="$PACKAGES block-mount kmod-fs-ext4 kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-vfat e2fsprogs kmod-usb-storage kmod-usb-storage-uas"

# 内核与网络协议栈加速 (TCP BBR 拥塞控制支持)
PACKAGES="$PACKAGES kmod-tcp-bbr"

# 文件共享 (Samba4 协议服务)
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"

# 注意：本工作流（25.12 / apk）暂不集成第三方软件包。
# 原因见文件头说明：apk 路径的第三方集成尚未完成，一旦把第三方包写入
# CUSTOM_PACKAGES，就会触发下面的 store 仓库同步并导致 make image 解析失败。
# 因此 OxiDNS、UniShare、luci-app-store 等第三方组件仅在 24.10 工作流中启用。

# ========== 系统级优化组件 ==========
# eMMC 寿命与 I/O：fstrim 定期 TRIM；zram-swap 为内存压缩交换，不写闪存
PACKAGES="$PACKAGES fstrim zram-swap"
# 中断分发与多队列：将网卡硬件中断分散到多个 CPU 核心
PACKAGES="$PACKAGES irqbalance luci-app-irqbalance"

# ========== 网络与多线 (双 2.5G) ==========
# iptables-nft / ip6tables-nft：为 mwan3、sqm-scripts 提供 iptables 虚拟依赖的确定性解析
PACKAGES="$PACKAGES iptables-nft ip6tables-nft"
PACKAGES="$PACKAGES mwan3 luci-app-mwan3"
PACKAGES="$PACKAGES sqm-scripts luci-app-sqm"
PACKAGES="$PACKAGES miniupnpd-nftables luci-app-upnp"
PACKAGES="$PACKAGES pbr luci-app-pbr"

# ========== 监控与运维 ==========
PACKAGES="$PACKAGES nlbwmon luci-app-nlbwmon"
PACKAGES="$PACKAGES vnstat2 luci-app-vnstat2"
PACKAGES="$PACKAGES netdata luci-app-netdata"
PACKAGES="$PACKAGES luci-app-cpulimit"
PACKAGES="$PACKAGES iperf3 coremark"

# ========== 无线增强 (MT7921) ==========
PACKAGES="$PACKAGES travelmate luci-app-travelmate"
PACKAGES="$PACKAGES wifischedule luci-app-wifischedule"
PACKAGES="$PACKAGES usteer luci-app-usteer dawn luci-app-dawn"

# ========== 安全与便捷 ==========
PACKAGES="$PACKAGES luci-app-advanced-reboot"
PACKAGES="$PACKAGES luci-app-commands"
PACKAGES="$PACKAGES luci-app-cpufreq"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
