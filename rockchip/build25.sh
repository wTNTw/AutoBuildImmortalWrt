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
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# 硬件驱动与无线网络支持 (针对 NanoPi R5C 等设备强化 2.5G 网卡与 MT7921 Wi-Fi 6)
PACKAGES="$PACKAGES kmod-r8125"
PACKAGES="$PACKAGES kmod-mt7921-common kmod-mt7921-firmware kmod-mt7921e"
PACKAGES="$PACKAGES iw iwinfo wpad-openssl"
PACKAGES="$PACKAGES kmod-btusb mt7921bt-firmware"

# 集成 OxiDNS (https://oxidns.org/openwrt)
PACKAGES="$PACKAGES luci-app-oxidns luci-i18n-oxidns-zh-cn"

# 文件共享 (Samba4 协议服务)
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 若构建 OxiDNS 则下载 luci 插件包并预置内核与 WebUI
if echo "$PACKAGES" | grep -q "luci-app-oxidns"; then
    echo "✅ 已选择 luci-app-oxidns，下载 luci-app-oxidns 及其语言包"
    mkdir -p /home/build/immortalwrt/packages
    OXIDNS_LUCI_URL=$(curl -s https://api.github.com/repos/svenshi/luci-app-oxidns/releases/latest | grep "browser_download_url.*luci-app-oxidns.*\.apk" | head -n1 | cut -d '"' -f 4)
    OXIDNS_I18N_URL=$(curl -s https://api.github.com/repos/svenshi/luci-app-oxidns/releases/latest | grep "browser_download_url.*luci-i18n-oxidns-zh-cn.*\.apk" | head -n1 | cut -d '"' -f 4)
    [ -n "$OXIDNS_LUCI_URL" ] && wget "$OXIDNS_LUCI_URL" -P /home/build/immortalwrt/packages/
    [ -n "$OXIDNS_I18N_URL" ] && wget "$OXIDNS_I18N_URL" -P /home/build/immortalwrt/packages/

    echo "✅ 下载并预置 OxiDNS core 二进制与 WebUI"
    mkdir -p files/usr/bin files/usr/share/oxidns
    OXIDNS_CORE_URL=$(curl -s https://api.github.com/repos/svenshi/oxidns/releases/latest | grep "browser_download_url.*aarch64-unknown-linux-musl\.tar\.gz" | head -n1 | cut -d '"' -f 4)
    if [ -n "$OXIDNS_CORE_URL" ]; then
        curl -sL "$OXIDNS_CORE_URL" | tar -xz -C /tmp/
        [ -f /tmp/oxidns ] && mv /tmp/oxidns files/usr/bin/oxidns && chmod +x files/usr/bin/oxidns
        [ -d /tmp/webui ] && rm -rf files/usr/share/oxidns/webui && mv /tmp/webui files/usr/share/oxidns/webui
    fi
fi


make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
