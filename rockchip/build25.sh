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

# 分区扩容 partexp 的运行时依赖（插件本体走「预置 apk + 首启安装」，见下方 partexp 段落）
# 该包声明 11 个依赖，其中 block-mount / e2fsprogs 上面已装；其余必须在这里进镜像，两条理由：
#   1) 首启安装先试 `apk add --no-network`，缺依赖会直接失败并退化成联网安装；对刚刷完机、
#      还没配好上网的设备，靠联网补齐并不可靠。
#   2) kmod-loop 是内核模块，必须与内核版本严格匹配，只能经构建期 apk 安装
#      （与上面 Nikki 内核依赖的处理同理）。
# 包名已逐一核对，在 25.12.1 / aarch64_generic 官方源中都存在：blkid/losetup/fdisk 是
# util-linux 的子包，resize2fs 是 e2fsprogs 的子包，但都作为独立包名发布，可直接写。
PACKAGES="$PACKAGES fdisk bc blkid parted btrfs-progs losetup resize2fs f2fs-tools kmod-loop"

# 内核与网络协议栈加速 (TCP BBR 拥塞控制支持)
PACKAGES="$PACKAGES kmod-tcp-bbr"

# 文件共享 (Samba4 协议服务)
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"

# 注意：本工作流（25.12 / apk）不能像 24.10 那样把零散 .apk 丢进本地 packages/ 目录，
# 因为 apk 只能经 packages/packages.adb 索引访问该目录，详见下方「OxiDNS」段落的处理。

# 集成 OxiDNS（第三方）：不使用 apk 安装，而是把官方发布包的文件直接铺入 files/，
# 详见下方「OxiDNS（第三方，改为文件注入）」段落的说明。不在 PACKAGES 中声明任何 oxidns 包。
ENABLE_OXIDNS=1

# 集成 Nikki（mihomo 代理，第三方）：交付方式是「预置 .apk + 首次开机 apk 安装」，不是文件注入。
# mihomo 核心随 nikki 包提供（/usr/libexec/nikki），不需要单独注入二进制。
# 完整理由、包来源与首启安装逻辑见下方「Nikki（mihomo 代理，第三方）」段落。
ENABLE_NIKKI=1

# 集成 netwizard（网络向导，第三方）：交付方式与 Nikki 相同，同为「预置 .apk + 首次开机安装」。
# ⚠️ 该向导一旦在 LuCI 里被使用，会按向导选项重写现有 network / wireless / dhcp 配置。
#    预装本身不影响现有配置（其 init 的 boot() 直接 return），但请知悉这一点；
#    完整理由、资产选择与真机兼容性证据见下方「netwizard（网络向导，第三方）」段落。
ENABLE_NETWIZARD=1

# 集成 partexp（分区扩容，第三方）：同为「预置 .apk + 首次开机安装」。
# ⚠️ 该插件会写分区表 / 格式化 / 调整根分区，属高风险操作。包内**没有 init 脚本**，
#    也没有 ucitrack 项，所以开机不会自动动作；只有用户在 LuCI 里显式点按钮
#    （ubus partexp.autopart）才会执行。它的运行时依赖已在上面的 PACKAGES 段落装进镜像。
ENABLE_PARTEXP=1

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
# 注：已移除 pbr / luci-app-pbr / luci-i18n-pbr-zh-cn（策略路由 / Policy Routing）
#     理由：与已集成的 Nikki(mihomo) 规则分流在作用域上重叠——两者同时作用于同一流量时，
#           nftables 标记/fwmark 与规则优先级易冲突，导致分流整体错乱；本机为单 WAN + mihomo
#           分流场景，不需要 IP/端口层的粗粒度选路。imm25.config 中该项本就为 "not set"，
#           此前是由本行显式拉入的，删除本行即可使固件不再包含该插件。
#     （实机侧已同步 apk del，含其自动孤儿依赖 resolveip）

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
# wifischedule：按时间开关无线，单射频场景下有一定意义，保留；菜单已改挂到「网络」下。
PACKAGES="$PACKAGES wifischedule luci-app-wifischedule luci-i18n-wifischedule-zh-cn"

# ========== 安全与便捷 ==========
# 已移除 advanced-reboot（高级重启：面向双系统/双恢复分区机型的分区切换重启，
# 本设备为单系统 eMMC 布局，无目标分区可选）与 commands（自定义命令：网页直连 shell，
# 功能可由 SSH 覆盖，且暴露任意命令执行面）。
PACKAGES="$PACKAGES luci-app-cpufreq luci-i18n-cpufreq-zh-cn"

# ========== Nikki 代理的依赖（本体走「预置 apk + 首启安装」，见下方段落） ==========
# nikki 的 Depends：libc ca-bundle curl yq firewall4 ip-full
#   kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy mihomo
# 这里只装**官方源**能提供的依赖；luci-app-nikki / nikki 由首启脚本用预置 .apk 安装。
# 注意：mihomo 核心**不是**独立包名，它打包在 nikki 包内部（安装后 /usr/libexec/nikki，
# 并自动注册 /usr/bin/mihomo alternative），所以不需要在 PACKAGES 里单列，也不必注入二进制。
# 内核模块依赖必须留在 PACKAGES 里经 apk 安装，才能与内核版本严格匹配。
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

    # ---- 不再向上游补 mihomo 二进制（2026-09-25 修正）----
    # 曾经的做法：若预置包里没有 mihomo*.apk，就从 MetaCubeX/mihomo 下载 linux-arm64 二进制
    # 放进 files/usr/bin/mihomo。实测证明这个判据是错的，而且代价很大：
    #   * mihomo 核心**打包在 nikki 包内部**，安装后位于 /usr/libexec/nikki；
    #     该包的 post-install 会注册 alternative：/usr/bin/mihomo -> /usr/libexec/nikki；
    #   * 于是注入的那份在首启安装后立刻被 alternative 覆盖，从头到尾没被使用过。
    #     真机证据（r37978）：/rom/usr/bin/mihomo 与 /usr/libexec/nikki 字节数完全相同
    #     （均 57,278,590），Release 体积因此多出约 30MB。
    # 现改为只做存在性检查并告警：内核由 nikki 包自带，不需要我们兜底。
    if ls "$NK_DST"/nikki-*.apk >/dev/null 2>&1; then
        echo "  OK 预置包已含 nikki-*.apk（内含 mihomo 核心 + /usr/bin/mihomo alternative，无需另补二进制）"
    else
        echo "  警告: 预置包中没有 nikki-*.apk —— mihomo 核心随该包提供，缺失会导致"
        echo "        首启装完后 /usr/bin/mihomo 不可用，请检查上游仓库结构是否变化。"
    fi
fi

# ============ 第三方插件预置 apk（通用）============
# 为什么不能在构建期装：25.12 是 apk，而 ImageBuilder 的本地 packages/ 目录只能经
# packages.adb 索引被 apk 看到，该索引在本镜像里生成不了（详见上面 Nikki 段落）；
# 而**设备端** `apk add --allow-untrusted <本地 .apk 文件>` 是可用的。因此统一做法是：
# 把 .apk 预置进固件 → 首次开机由 /etc/boot-tuning.sh 安装（包会被 apk 正常登记，可升级卸载）。
#
# 取包时必须选对 release 资产 —— 两个 SDK 分支的**包格式不同**，选错设备直接装不上：
#   SNAPSHOT-<arch>.tar.gz       -> 内含 .apk（apk-tools 3.x，本项目走这条）
#   openwrt-24.10-<arch>.tar.gz  -> 内含 .ipk（opkg 用，本项目不取）
# 这类插件多为 PKGARCH:=all（装入后标 noarch），各架构资产内容一致；这里仍按设备架构
# aarch64_generic 取，与 DISTRIB_ARCH 对齐。
#
# 统一收在下面两个函数里，避免每个插件各写一份：日后改目录约定或上游资产命名时只改一处。
#
# 完整的踩坑记录（资产格式、ucitrack 注册顺序、包自带 uci-defaults、依赖进 PACKAGES）见
# docs/solutions/build/third-party-apk-preset-install.md —— 新增插件前建议先读一遍。
preset_plugin_apks() {
    local name="$1" repo="$2" dst="$3"
    local tmp="/tmp/preset-apk-$name"
    local url

    echo "---- $name: 下载 release 并预置 apk ----"
    mkdir -p "$dst"
    rm -rf "$tmp"; mkdir -p "$tmp"

    url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" \
          | grep "browser_download_url.*SNAPSHOT-aarch64_generic\.tar\.gz" | head -n1 | cut -d '"' -f 4)
    if [ -z "$url" ]; then
        echo "  ⚠️ $repo 的 release 资产里找不到 SNAPSHOT-aarch64_generic.tar.gz，固件将不含 $name"
        return 0
    fi
    if ! wget -q "$url" -O "$tmp/rel.tar.gz" || ! tar -xzf "$tmp/rel.tar.gz" -C "$tmp"; then
        echo "  ⚠️ $name release 下载或解包失败，固件将不含该插件"
        return 0
    fi
    # 资产内部固定放在 packages_ci/ 下，故用 find 而不是写死路径
    find "$tmp" -name '*.apk' -exec cp -f {} "$dst"/ \;
    echo "---- $name 预置的 apk 清单 ----"
    ls -la "$dst" 2>/dev/null
}

# 预置目录里最终没有预期的包时，提前把问题暴露在构建日志里 ——
# 首启脚本只会安静地记一行日志跳过，不主动检查就会刷出「以为装了、其实没装」的固件。
require_preset_apk() {
    local name="$1" pattern="$2" dst="$3"
    if ! ls "$dst"/$pattern >/dev/null 2>&1; then
        echo "  ⚠️ $name 的预置目录里没有 $pattern，固件将不含该插件"
    fi
}

# ---- netwizard（网络向导）----
# ⚠️ 行为提示：该向导一旦在 LuCI 里被使用，会按向导选项重写现有 network / wireless / dhcp
#    配置。预装本身不影响现有配置（其 init 的 boot() 直接 return），详见 99-custom.sh 的说明。
# 兼容性实证（2026-09-26 读目标机：ImmortalWrt 25.12.1 r37978 / NanoPi R5C / apk-tools 3.0.5）：
# 该机上已装着与本 release 同版本的包，说明这套 apk 在本项目的 apk 上可直接安装：
#   luci-app-netwizard-2.1.5-r20260312              noarch  depends: libc
#   luci-i18n-netwizard-zh-cn-26.060.49879~201cb64  noarch
if [ "$ENABLE_NETWIZARD" = "1" ]; then
    NW_DST=/home/build/immortalwrt/files/usr/share/netwizard-apk
    preset_plugin_apks netwizard sirpdboy/luci-app-netwizard "$NW_DST"
    require_preset_apk netwizard 'luci-app-netwizard-*.apk' "$NW_DST"
fi

# ---- partexp（分区扩容）----
# 该包没有 /etc/init.d，也没有 /usr/share/ucitrack，所以首启安装后**不需要** enable 或注册触发器；
# 它自带的 /etc/uci-defaults/zzz_luci-app-partexp（chmod +x 两个可执行文件 + rpcd restart）
# 会由 apk 的 default_postinst 在装包时自动执行并删除自身（见 /lib/functions.sh 的
# default_postinst：按本包 file list 匹配 /etc/uci-defaults/ 后逐条 source 再 rm）。
# 注意该包 ship 的两个可执行文件权限是 0644，全靠那段 uci-defaults 补 +x；
# 实机已验证这段确实跑到了（见下方实证），若日后 default_postinst 行为变化会表现为
# 「包装上了但 ubus partexp 对象不出现」。
# 兼容性实证（2026-09-26 读目标机，同 netwizard）：该机上已装着与本 release 同版本的包，
# 且 /usr/bin/partexp 与 /usr/libexec/rpcd/partexp 均为 0755、`ubus -v list partexp` 已注册：
#   luci-app-partexp-2.0.5-r20260318              noarch
#   luci-i18n-partexp-zh-cn-25.355.34625~38e15b6  noarch
if [ "$ENABLE_PARTEXP" = "1" ]; then
    PE_DST=/home/build/immortalwrt/files/usr/share/partexp-apk
    preset_plugin_apks partexp sirpdboy/luci-app-partexp "$PE_DST"
    require_preset_apk partexp 'luci-app-partexp-*.apk' "$PE_DST"
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
