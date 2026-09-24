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
  # 【重要】25.12 使用 apk。ImageBuilder 的本地 packages/ 目录只能通过 packages.adb 索引
  # 被 apk 看到，而该索引在本镜偯中不存在也无法生成（实测报 "No such file or directory"），
  # 因此「把零散 .apk 丢进 packages/」的做法在本工作流中完全无效，只会得到 no such package。
  # 所以这里不再同步 wukongdaily 的 apk bundle。
  # 第三方组件改用其官方 apk 仓库（自带 ADB 索引），见下方 iStore 段落。
  echo "ℹ️ 第三方包将仅从官方 apk 仓库解析：$CUSTOM_PACKAGES"
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories信息——————"
cat repositories
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-app-diskman luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-app-package-manager luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-app-firewall luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"
# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-app-dockerman luci-i18n-dockerman-zh-cn docker"
    echo "Adding package: luci-app-dockerman luci-i18n-dockerman-zh-cn docker"
fi
# 文件管理器
PACKAGES="$PACKAGES luci-app-filemanager luci-i18n-filemanager-zh-cn"

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
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"

# 注意：本工作流（25.12 / apk）不能像 24.10 那样把零散 .apk 丢进本地 packages/ 目录，
# 因为 apk 只能经 packages/packages.adb 索引访问该目录，详见下方「OxiDNS」段落的处理。

# 集成 OxiDNS（第三方）：不使用 apk 安装，而是把官方发布包的文件直接铺入 files/，
# 详见下方「OxiDNS（第三方，改为文件注入）」段落的说明。不在 PACKAGES 中声明任何 oxidns 包。
ENABLE_OXIDNS=1

# ========== 系统级优化组件 ==========
# eMMC 寿命与 I/O：fstrim 定期 TRIM；zram-swap 为内存压缩交换，不写闪存
PACKAGES="$PACKAGES fstrim zram-swap"
# 中断分发与多队列：将网卡硬件中断分散到多个 CPU 核心
PACKAGES="$PACKAGES irqbalance luci-app-irqbalance luci-i18n-irqbalance-zh-cn"

# ========== 网络与多线 (双 2.5G) ==========
# iptables-nft / ip6tables-nft：为 mwan3、sqm-scripts 提供 iptables 虚拟依赖的确定性解析
PACKAGES="$PACKAGES iptables-nft ip6tables-nft"
PACKAGES="$PACKAGES mwan3 luci-app-mwan3 luci-i18n-mwan3-zh-cn"
PACKAGES="$PACKAGES sqm-scripts luci-app-sqm luci-i18n-sqm-zh-cn"
PACKAGES="$PACKAGES miniupnpd-nftables luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES pbr luci-app-pbr luci-i18n-pbr-zh-cn"

# ========== 监控与运维 ==========
PACKAGES="$PACKAGES nlbwmon luci-app-nlbwmon luci-i18n-nlbwmon-zh-cn"
PACKAGES="$PACKAGES vnstat2 luci-app-vnstat2 luci-i18n-vnstat2-zh-cn"
PACKAGES="$PACKAGES netdata luci-app-netdata luci-i18n-netdata-zh-cn"
PACKAGES="$PACKAGES luci-app-cpulimit luci-i18n-cpulimit-zh-cn"
PACKAGES="$PACKAGES iperf3 coremark"

# ========== 无线增强 (MT7921) ==========
PACKAGES="$PACKAGES travelmate luci-app-travelmate luci-i18n-travelmate-zh-cn"
PACKAGES="$PACKAGES wifischedule luci-app-wifischedule luci-i18n-wifischedule-zh-cn"
PACKAGES="$PACKAGES usteer luci-app-usteer luci-i18n-usteer-zh-cn dawn luci-app-dawn luci-i18n-dawn-zh-cn"

# ========== 安全与便捷 ==========
PACKAGES="$PACKAGES luci-app-advanced-reboot luci-i18n-advanced-reboot-zh-cn"
PACKAGES="$PACKAGES luci-app-commands luci-i18n-commands-zh-cn"
PACKAGES="$PACKAGES luci-app-cpufreq luci-i18n-cpufreq-zh-cn"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ============ iStore 官方 apk 仓库 ============
# iStore 为 apk 平台（OpenWrt 25.12+）单独维护了自带 ADB 索引的仓库，
# 仓库地址来自其官方安装器 is-opkg 中的 FEEDS_SERVER 定义：
#   USE_APK 分支 -> https://istore.istoreos.com/repo-apk  (索引 packages.adb)
# 与 24.10 的 ipk 仓库(.../repo/...)不同，这里是原生 .apk，可直接被 apk 解析，
# 所以无需依赖本地 packages/ 索引，也不会有 no such package 问题。
if echo " $PACKAGES " | grep -q " luci-app-store "; then
    # luci-app-store 是 Lua/CBI 应用；25.12 的 JS 版 LuCI 默认不带 cbi.lua，
    # 与 iStore 官方 reinstall 脚本的兜底逻辑一致，这里显式补上兼容层
    PACKAGES="$PACKAGES luci-compat luci-lua-runtime"

    # 【签名信任】iStore 的仓库索引是签名的，而镜像构建器默认开启签名校验
    # （我们的 imm25.config 中 CONFIG_SIGNATURE_CHECK=y，Makefile 会传 --keys-dir $(TOPDIR)/keys），
    # 但它不认识 iStore 的密钥，会报 “UNTRUSTED signature” 并直接弃用该仓库。
    # 官方 is-opkg 的做法就是把公钥装进 /etc/apk/keys/，这里同样装进镜像构建器的 keys 目录。
    KEYS_DIR="/home/build/immortalwrt/keys"
    mkdir -p "$KEYS_DIR"
    if curl -fsSL "https://istore.istoreos.com/repo-apk/istore-apk.pem" -o "$KEYS_DIR/istore.pem"; then
        echo "✅ 已安装 iStore 公钥: $KEYS_DIR/istore.pem"
    else
        echo "⚠️ iStore 公钥下载失败，仓库索引将因签名未受信任而被弃用"
    fi

    REPO_FILE="/home/build/immortalwrt/repositories"
    [ -f "$REPO_FILE" ] || REPO_FILE="repositories"
    ISTORE_APK_INDEX="https://istore.istoreos.com/repo-apk/all/store/packages.adb"
    if [ -f "$REPO_FILE" ] && ! grep -qF "$ISTORE_APK_INDEX" "$REPO_FILE"; then
        printf '\n%s\n' "$ISTORE_APK_INDEX" >> "$REPO_FILE"
        echo "✅ 已追加 iStore 官方 apk 仓库: $ISTORE_APK_INDEX"
    else
        echo "ℹ️ iStore 仓库已在列表中，或 repositories 文件不存在"
    fi
    echo "---- 当前 repositories ----"
    cat "$REPO_FILE" 2>/dev/null
    echo "---- keys 目录 ----"
    ls -la "$KEYS_DIR" 2>/dev/null
fi

# ============ OxiDNS（第三方，改为文件注入）============
# 为何不用 apk 安装：25.12 是 apk，而 ImageBuilder 无法把第三方 .apk 装进固件：
#   - 本地 packages/ 目录需 packages.adb 索引，而该索引的生成规则带
#     `--sign keys/local-private-key.pem`，密钥缺失时 mkndx 直接失败，
#     又因规则结尾是 `|| true` 且输出进了 /dev/null，错误被完全掩盖；
#   - 即使生成了索引，镜像构建器的 apk 调用不会带 --allow-untrusted，
#     未签名的第三方包仍可能被拒。
# 因此改为：下载 OxiDNS 官方发布包（Architecture: all 的 .ipk，本质是 tar.gz），
# 直接解出 data.tar.gz 铺到 files/，由 make image 的 FILES= 机制覆盖进 rootfs。
# 文件内容与 .apk 一致（同一源码产物），且权限位会被保留。
# 注意：这种方式下 apk 数据库不登记该包，因此不能再用 apk 卸载/升级它。
if [ "$ENABLE_OXIDNS" = "1" ]; then
    echo "---- OxiDNS: 从官方 ipk 提取文件到 files/ ----"
    OXI_API=https://api.github.com/repos/svenshi/luci-app-oxidns/releases/latest
    OXI_APP_URL=$(curl -s "$OXI_API" | grep "browser_download_url.*luci-app-oxidns.*\.ipk" | head -n1 | cut -d '"' -f 4)
    OXI_I18N_URL=$(curl -s "$OXI_API" | grep "browser_download_url.*luci-i18n-oxidns-zh-cn.*\.ipk" | head -n1 | cut -d '"' -f 4)

    OXI_TMP=/tmp/oxidns-pkgs
    rm -rf "$OXI_TMP"; mkdir -p "$OXI_TMP"
    idx=0
    for u in "$OXI_APP_URL" "$OXI_I18N_URL"; do
        [ -z "$u" ] && continue
        idx=$((idx+1))
        d="$OXI_TMP/p$idx"
        mkdir -p "$d"
        if wget -q "$u" -O "$d/pkg.ipk"; then
            tar -xzf "$d/pkg.ipk" -C "$d" 2>/dev/null
            if [ -f "$d/data.tar.gz" ] && tar -xzf "$d/data.tar.gz" -C files/; then
                echo "  OK $(basename "$u") 已铺入 files/"
            else
                echo "  警告: $(basename "$u") 解包失败"
            fi
        else
            echo "  警告: 下载失败 $u"
        fi
    done

    # 预置 oxidns 内核与 WebUI（与 24.10 行为一致，开箱即用，免设备端联网下载）
    echo "---- 预置 oxidns 内核与 WebUI ----"
    mkdir -p files/usr/bin files/usr/share/oxidns
    OXIDNS_CORE_URL=$(curl -s https://api.github.com/repos/svenshi/oxidns/releases/latest | grep "browser_download_url.*aarch64-unknown-linux-musl\.tar\.gz" | head -n1 | cut -d '"' -f 4)
    if [ -n "$OXIDNS_CORE_URL" ]; then
        curl -sL "$OXIDNS_CORE_URL" | tar -xz -C /tmp/
        [ -f /tmp/oxidns ] && mv /tmp/oxidns files/usr/bin/oxidns && chmod +x files/usr/bin/oxidns
        [ -d /tmp/webui ] && rm -rf files/usr/share/oxidns/webui && mv /tmp/webui files/usr/share/oxidns/webui
        echo "  OK oxidns core + webui 已就位"
    fi

    echo "---- files/ 中 OxiDNS 相关文件 ----"
    ls -la files/etc/init.d/oxidns files/usr/libexec/rpcd/luci.oxidns 2>/dev/null
    ls -la files/www/luci-static/resources/view/oxidns/ 2>/dev/null | head -n 8
    ls -la files/usr/lib/lua/luci/i18n/oxidns.zh-cn.lmo 2>/dev/null
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
