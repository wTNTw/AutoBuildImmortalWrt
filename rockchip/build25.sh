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

# 集成 Nikki（mihomo 代理，第三方）：同样采用「文件注入」，理由与 OxiDNS 相同。
# 三个包（luci-app-nikki / nikki / mihomo）从社区源 dl.openwrt.ai 的 opkg 格式 ipk 解包注入，
# 其余依赖（含内核模块，必须匹配内核版本）走官方源经 apk 正常安装。
ENABLE_NIKKI=1

# ========== 系统级优化组件 ==========
# eMMC 寿命与 I/O：fstrim 定期 TRIM；zram-swap 为内存压缩交换，不写闪存
PACKAGES="$PACKAGES fstrim zram-swap"
# 中断分发与多队列：将网卡硬件中断分散到多个 CPU 核心
# 注：其 LuCI 菜单项默认挂在「服务」下，已由 files/usr/share/luci/menu.d/luci-app-irqbalance.json
#     改挂到「网络」菜单（覆盖同名菜单文件，不会产生重复入口；ACL 按应用名授权，无需改动）
PACKAGES="$PACKAGES irqbalance luci-app-irqbalance luci-i18n-irqbalance-zh-cn"

# ========== 网络 (双 2.5G) ==========
# iptables-nft / ip6tables-nft：为 sqm-scripts 提供 iptables 虚拟依赖的确定性解析
PACKAGES="$PACKAGES iptables-nft ip6tables-nft"
# 注：已移除 mwan3 / luci-app-mwan3（本机为单 WAN 场景，多线负载均衡无对象）
PACKAGES="$PACKAGES sqm-scripts luci-app-sqm luci-i18n-sqm-zh-cn"
# 注：upnp 的 LuCI 菜单项默认挂在「服务」下，已由 files/usr/share/luci/menu.d/luci-app-upnp.json
#     改挂到「网络」菜单（覆盖同名菜单文件；title 保持原串不变，以便 luci-i18n-upnp-zh-cn 仍能汉化）
PACKAGES="$PACKAGES miniupnpd-nftables luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES pbr luci-app-pbr luci-i18n-pbr-zh-cn"

# ========== DNS 广告过滤 (AdGuardHome) ==========
# 均为官方源包（非第三方注入），已实测存在于 25.12.1 / aarch64_generic 源：
#   adguardhome-0.107.76-r1.apk                    -> packages 源，核心二进制 /usr/bin/AdGuardHome
#   luci-app-adguardhome-26.236.50544~cb5d434.apk  -> luci 源，LuCI 配置界面
# 注意事项：
#   1) 上游未提供 luci-i18n-adguardhome-zh-cn（luci 源仅有 -lo 等少数语言包），界面为英文；
#   2) 服务不会自行运行：init 脚本取 UCI 配置 adguardhome.config.enabled（默认 0），
#      enabled != 1 时 start_service 直接 return，故不会抢先占用 53 端口与 dnsmasq 冲突。
#      构建期 ImageBuilder 仍会为其创建 rc.d 软链（日志 "Enabling adguardhome"），这只是启用标记。
#      需要接管 DNS 时，在 LuCI 中启用并配置重定向即可；机制详见
#      docs/solutions/build/imagebuilder-rootfs-finalize-semantics.md
PACKAGES="$PACKAGES adguardhome luci-app-adguardhome"

# ========== 监控与运维 ==========
# 带宽监控类插件已全部移除：nlbwmon（连接级记账）、vnstat2（接口级记账）、
# netdata（秒级全指标采集，资源占用偏高）；本地仅保留按需使用的吞吐测试工具。
PACKAGES="$PACKAGES luci-app-cpulimit luci-i18n-cpulimit-zh-cn"
PACKAGES="$PACKAGES iperf3 coremark"

# ========== 无线增强 (MT7921) ==========
# 已移除 travelmate / usteer / dawn：无内置射频（或单射频）时无作用对象，
# 且 dawn 默认 kicking 可能主动踢开客户端、usteer 与 dawn 功能重叠。
PACKAGES="$PACKAGES wifischedule luci-app-wifischedule luci-i18n-wifischedule-zh-cn"

# ========== 安全与便捷 ==========
PACKAGES="$PACKAGES luci-app-advanced-reboot luci-i18n-advanced-reboot-zh-cn"
PACKAGES="$PACKAGES luci-app-commands luci-i18n-commands-zh-cn"
PACKAGES="$PACKAGES luci-app-cpufreq luci-i18n-cpufreq-zh-cn"

# ========== Nikki 代理的依赖（本体走文件注入，见下方段落） ==========
# nikki 的 Depends：libc ca-bundle curl yq firewall4 ip-full
#   kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy mihomo
# 其中 luci-app-nikki / nikki / mihomo 三个包改为文件注入；
# 其余依赖都是官方源包，正常经 apk 安装（内核模块必须走 apk 才能匹配内核版本）。
PACKAGES="$PACKAGES ca-bundle yq ip-full rpcd-mod-ucode"
PACKAGES="$PACKAGES kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy"
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

# ============ Nikki（mihomo 代理，第三方）============
# 交付方式：预置 .apk 进固件 + 首次开机用 apk 安装（不是“文件注入”）。
#
# 为什么这样做：
#   - 25.12 是 apk，而 ImageBuilder **构建期**无法安装第三方 .apk：
#     本地 packages/ 目录需要 packages.adb 索引，而该索引的生成规则会调用
#     apk mkndx，实测在该镜像里直接段错误（exit 139），且错误被 `|| true` 掩盖；
#   - 但**设备端** `apk add --allow-untrusted <本地 .apk 文件>` 是可用的（已在设备上验证：
#     用户手动安装的 nikki / mihomo-meta 就是走这条路，apk 正常登记）。
#   => 因此把 .apk 预置进固件，由首次开机脚本调用 apk 安装，包能被包管理器登记、可升级卸载。
#
# 源：wukongdaily/apk 仓库（其打包时 feed 路径为 /feed，与设备上看到的 origin 一致）。
# 这里用 git clone 而非写死文件名，避免上游改名就失效。
if [ "$ENABLE_NIKKI" = "1" ]; then
    echo "---- Nikki: 收集 apk 并预置进固件 ----"
    NK_SRC=/tmp/wukong-apk
    NK_DST=/home/build/immortalwrt/files/usr/share/nikki-apk
    mkdir -p "$NK_DST"
    rm -rf "$NK_SRC"

    if git clone --depth=1 https://github.com/wukongdaily/apk.git "$NK_SRC" >/dev/null 2>&1; then
        # 机型 apk 架构为 aarch64_generic，故只取上游 run/arm64/（generic 构建）；
        # run/arm64-a53/ 的包标记为 aarch64_cortex-a53，架构不匹配会被 apk 直接判为
        # uninstallable，导致首启安装失败（实测 2026-09-25，ImmortalWrt 25.12.1/rockchip）。
        # 1) 本来就是 .apk 的
        find "$NK_SRC" -path '*nikki*' -path '*/arm64/*' -name '*.apk' -exec cp -f {} "$NK_DST"/ \; 2>/dev/null
        # 2) 打包在 makeself .run 里的
        for r in $(find "$NK_SRC" -path '*nikki*' -path '*/arm64/*' -name '*.run' 2>/dev/null); do
            echo "  解包 $(basename "$r")"
            rm -rf /tmp/nk-unpack; mkdir -p /tmp/nk-unpack
            sh "$r" --target /tmp/nk-unpack --noexec >/dev/null 2>&1
            find /tmp/nk-unpack -name '*.apk' -exec cp -f {} "$NK_DST"/ \; 2>/dev/null
        done
        # 兜底：若上游目录结构变化导致一个 generic 包都没取到，回退为全部架构（宁可多预置也不留空）
        if ! ls "$NK_DST"/*.apk >/dev/null 2>&1; then
            echo "  警告: 未取到 arm64(generic) 预置包，回退为全部架构"
            find "$NK_SRC" -path '*nikki*' -name '*.apk' -exec cp -f {} "$NK_DST"/ \; 2>/dev/null
        fi
    else
        echo "  警告: 无法克隆 wukongdaily/apk，跳过 Nikki 预置"
    fi

    echo "---- 预置的 apk 清单 ----"
    ls -la "$NK_DST" 2>/dev/null

    # ---- 去重：同名包只保留最高版本 ----
    # 上游仓库同一架构目录下也可能保留历史版本（如 luci-app-nikki 的多个版本），
    # 而首启 rc.local 执行 `apk add --allow-untrusted /usr/share/nikki-apk/*.apk`；
    # 同名多版本一次性安装会因包冲突导致首启安装失败，故此处按“包名”去重、仅保留版本最高者。
    if ls "$NK_DST"/*.apk >/dev/null 2>&1; then
        nk_dedup=/tmp/nikki-dedup
        rm -f "$nk_dedup"/*.apk 2>/dev/null
        mkdir -p "$nk_dedup"
        for f in "$NK_DST"/*.apk; do
            b=$(basename "$f")
            # 包名 = 去掉从首个“-数字”开始的后缀（版本号总以数字开头）
            pkg=$(printf '%s' "$b" | sed -E 's/-[0-9].*//')
            if printf '1.2\n1.10\n' | sort -V >/dev/null 2>&1; then
                keep=$(ls "$NK_DST"/"${pkg}"-*.apk 2>/dev/null | sort -V | tail -n1)
            else
                keep=$(ls "$NK_DST"/"${pkg}"-*.apk 2>/dev/null | sort | tail -n1)
            fi
            [ -n "$keep" ] && cp -f "$keep" "$nk_dedup"/
        done
        rm -f "$NK_DST"/*.apk
        cp -f "$nk_dedup"/*.apk "$NK_DST"/ 2>/dev/null
        echo "---- 去重后预置包（每个包仅保留最高版本）----"
        ls -la "$NK_DST" 2>/dev/null
    fi

    # 若预置包中不含 mihomo 内核，则从上游补一个二进制到 /usr/bin/mihomo
    # （nikki 的 /etc/init.d/nikki 固定 PROG="/usr/bin/mihomo"）
    if ! ls "$NK_DST"/mihomo*.apk >/dev/null 2>&1; then
        echo "  预置包中无 mihomo，改为从上游补内核二进制"
        mkdir -p files/usr/bin
        MH_URL=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "browser_download_url.*linux-arm64.*\.gz" | head -n1 | cut -d '"' -f 4)
        if [ -n "$MH_URL" ]; then
            if wget -qO- "$MH_URL" | gzip -dc > files/usr/bin/mihomo; then
                chmod 755 files/usr/bin/mihomo
                echo "  OK mihomo 内核 -> files/usr/bin/mihomo ($(du -h files/usr/bin/mihomo | cut -f1))"
            else
                echo "  警告: mihomo 内核下载失败"
            fi
        else
            echo "  警告: 未解析到 mihomo 下载地址"
        fi
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
