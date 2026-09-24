#!/bin/sh
# ============================================================================
# 98-docker-nftables-backend.sh —— 让 dockerd 使用 nftables 防火墙后端
# ----------------------------------------------------------------------------
# 目的：消除 LuCI「状态 → nftables」页的告警：
#   "Legacy rules detected / There are legacy iptables rules present on the
#    system. Mixing iptables and nftables rules is discouraged ..."
#
# 实测根因（ImmortalWrt 25.12.1 + Docker 29.6.1，2026-09-25）：
#   * 系统里并不存在真正的 legacy iptables：无 iptables-legacy* 二进制、无 ebtables；
#   * 告警来自 /www/luci-static/resources/view/status/nftables.js 的 checkLegacyRules()：
#     它先找 /usr/sbin/iptables-legacy-save，找不到就回退执行 iptables-save（nf_tables 版），
#     只要输出里出现 "-A " 行，就判定为「legacy iptables 混用」；
#   * dockerd 默认用 iptables 后端，把规则写进 nft 的 table ip filter / table ip nat，
#     与 fw4 的 table inet fw4 并存 → 被上述判断误报。
#
# 修复：Docker 29+ 新增 --firewall-backend（iptables|nftables）。切到 nftables 后，
#   dockerd 改用自己的 nft 表（table ip docker-bridges），不再产生任何 iptables 规则，
#   iptables-save 为空 → 告警消失，系统成为真正的纯 nftables；容器 NAT/端口映射由
#   Docker 自身的 nft 规则完成，跨区过滤仍由 fw4（含 99-custom.sh 注入的 docker zone）负责。
#
# 落点：OpenWrt 的 /etc/init.d/dockerd 由 UCI /etc/config/dockerd 生成 /tmp/dockerd/daemon.json，
#   它只支持 iptables/ip6tables 开关、不认 firewall-backend；但支持 alt_config_file，
#   把 daemon.json 指到我们预写的文件即可。
#
# 兼容性：files/ 被所有机型共用（含 24.10 等较旧 docker），而 daemon.json 出现未知键会让
#   旧版 dockerd 拒绝启动，故先探测 dockerd 是否支持 --firewall-backend，不支持则直接跳过。
#
# 回滚：删除本文件与 /etc/docker/daemon.json，并
#   uci -q delete dockerd.globals.alt_config_file && uci -q commit dockerd
# ============================================================================

# 未安装 dockerd 则跳过（仍返回 0，以便被 uci-defaults 正常清理）
command -v dockerd >/dev/null 2>&1 || exit 0

# 旧版 docker 不支持该后端：保持默认 iptables 后端，不做改动
if ! dockerd --help 2>&1 | grep -q -- '--firewall-backend'; then
	echo "98-docker-nftables-backend: dockerd 不支持 --firewall-backend，跳过切换"
	exit 0
fi

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
	"data-root": "/opt/docker/",
	"log-level": "warn",
	"iptables": true,
	"ip6tables": false,
	"firewall-backend": "nftables"
}
EOF

if [ -f /etc/config/dockerd ]; then
	uci -q set dockerd.globals.alt_config_file='/etc/docker/daemon.json'
	uci -q commit dockerd
	echo "98-docker-nftables-backend: 已切换 dockerd 为 nftables 防火墙后端"
fi

# 若 dockerd 已在运行（非首启场景），重启使其生效
if /etc/init.d/dockerd running >/dev/null 2>&1; then
	/etc/init.d/dockerd restart >/dev/null 2>&1
fi

exit 0
