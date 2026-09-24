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

# 注意：本工作流（25.12 / apk）不能像 24.10 那样把零散 .apk 丢进本地 packages/ 目录，
# 因为 apk 只能经 packages/packages.adb 索引访问该目录，详见下方「OxiDNS」段落的处理。

# 集成 OxiDNS（第三方）：其 .apk 只发布在 GitHub Releases，没有在线索引，
# 因此下载后需自行生成 apk 本地索引（packages.adb）并签名，见下方段落。
PACKAGES="$PACKAGES luci-app-oxidns luci-i18n-oxidns-zh-cn"

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

# ============ OxiDNS（第三方；开源自建 apk 本地索引）============
# apk 只能经 packages/packages.adb 索引看到 packages/ 目录，因此这里做三件事：
#   1) 把 OxiDNS 的 .apk 下载进 packages/
#   2) 准备本地签名密钥 keys/local-private-key.pem
#      （ImageBuilder 的 package_index 会传 --sign 这个路径，但只有当 _check_keys 生成过后才存在；
#        这里提前生成，同时让本地索引的签名可被 keys/ 里的公钥信任）
#   3) 自行生成并签名索引 packages.adb
if echo " $PACKAGES " | grep -q " luci-app-oxidns "; then
    PKG_DIR=/home/build/immortalwrt/packages
    KEYS_DIR=/home/build/immortalwrt/keys
    HOST_BIN=/home/build/immortalwrt/staging_dir/host/bin
    mkdir -p "$PKG_DIR" "$KEYS_DIR"

    echo "---- 下载 OxiDNS 的 LuCI 插件与中文语言包 (apk) ----"
    OXIDNS_LUCI_URL=$(curl -s https://api.github.com/repos/svenshi/luci-app-oxidns/releases/latest | grep "browser_download_url.*luci-app-oxidns.*\.apk" | head -n1 | cut -d '"' -f 4)
    OXIDNS_I18N_URL=$(curl -s https://api.github.com/repos/svenshi/luci-app-oxidns/releases/latest | grep "browser_download_url.*luci-i18n-oxidns-zh-cn.*\.apk" | head -n1 | cut -d '"' -f 4)
    [ -n "$OXIDNS_LUCI_URL" ] && wget -q "$OXIDNS_LUCI_URL" -P "$PKG_DIR/" && echo "  OK $(basename "$OXIDNS_LUCI_URL")"
    [ -n "$OXIDNS_I18N_URL" ] && wget -q "$OXIDNS_I18N_URL" -P "$PKG_DIR/" && echo "  OK $(basename "$OXIDNS_I18N_URL")"

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

    echo "---- packages/ 现有内容 ----"
    ls -la "$PKG_DIR" 2>/dev/null | head -n 30

    if [ ! -s "$KEYS_DIR/local-private-key.pem" ] && [ -x "$HOST_BIN/openssl" ]; then
        echo "---- 生成本地签名密钥（照搬 ImageBuilder _check_keys 的做法）----"
        "$HOST_BIN/openssl" ecparam -name prime256v1 -genkey -noout -out "$KEYS_DIR/local-private-key.pem" 2>/dev/null
        sed -i '1s/^/untrusted comment: Local build key\n/' "$KEYS_DIR/local-private-key.pem" 2>/dev/null
        "$HOST_BIN/openssl" ec -in "$KEYS_DIR/local-private-key.pem" -pubout > "$KEYS_DIR/local-public-key.pem" 2>/dev/null
        sed -i '1s/^/untrusted comment: Local build key\n/' "$KEYS_DIR/local-public-key.pem" 2>/dev/null
    fi
    echo "---- keys/ 内容 ----"
    ls -la "$KEYS_DIR" 2>/dev/null | head -n 20

    if [ -x "$HOST_BIN/apk" ]; then
        echo "---- 生成并签名本地 apk 索引 ----"
        ( cd "$PKG_DIR" && "$HOST_BIN/apk" mkndx \
            --keys-dir "$KEYS_DIR" \
            --sign "$KEYS_DIR/local-private-key.pem" \
            --allow-untrusted --output packages.adb ./*.apk )
        echo "mkndx exit=$?"
        ls -la "$PKG_DIR/packages.adb" 2>/dev/null || echo "警告: packages.adb 未生成"
    else
        echo "警告: 未找到 $HOST_BIN/apk，跳过本地索引生成（将由 Makefile 的 package_index 尝试）"
    fi
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
