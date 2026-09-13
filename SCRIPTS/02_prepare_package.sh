#!/bin/bash
clear

### 基础部分 ###
# 使用 O2 级别的优化
sed -i 's/Os/O2/g' include/target.mk
# 更新 Feeds
./scripts/feeds update -a
./scripts/feeds install -a

### ZRAM：补充 lzo-rle 并设为 LuCI 默认算法 ###
LUCI_SYSTEM_JS="./feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/system.js"

if [ -f "$LUCI_SYSTEM_JS" ]; then

    if grep -Fq "o.value('lzo-rle', 'lzo-rle');" "$LUCI_SYSTEM_JS"; then
        echo "ZRAM LuCI: upstream already provides lzo-rle, skip adding option"
    elif grep -Fq "o.value('lzo', 'lzo');" "$LUCI_SYSTEM_JS"; then
        echo "ZRAM LuCI: add lzo-rle option"
        sed -i "/o.value('lzo', 'lzo');/{h;s/o.value('lzo', 'lzo');/o.value('lzo-rle', 'lzo-rle');/;p;g;}" \
            "$LUCI_SYSTEM_JS"
    else
        echo "ZRAM LuCI: lzo option pattern changed, skip adding lzo-rle"
    fi

    if grep -Fq "o.default     = 'lzo-rle';" "$LUCI_SYSTEM_JS"; then
        echo "ZRAM LuCI: default already lzo-rle, skip changing default"
    elif grep -Fq "o.default     = 'lzo';" "$LUCI_SYSTEM_JS"; then
        echo "ZRAM LuCI: change default from lzo to lzo-rle"
        sed -i "s/o.default     = 'lzo';/o.default     = 'lzo-rle';/" \
            "$LUCI_SYSTEM_JS"
    else
        echo "ZRAM LuCI: default algorithm pattern changed, skip changing default"
    fi

    echo "===== ZRAM LuCI config ====="
    grep -n -A8 -B2 "zram_comp_algo" "$LUCI_SYSTEM_JS" || true

else
    echo "ZRAM LuCI: system.js not found, skip"
fi

# 定义预期的内核版本
SUPPORTED_KERNEL="6.12"

current_version=$(sed -n 's/^KERNEL_PATCHVER:=//p' ./target/linux/rockchip/Makefile) # 如 6.12
if [ -z "${current_version}" ]; then
    echo "Error: Failed to extract KERNEL_PATCHVER from ./target/linux/rockchip/Makefile"
    exit 1
fi
if [[ "${SUPPORTED_KERNEL}" != "${current_version}" ]]; then
    echo "##########
      错误：
      编译的内核版本为 ${current_version} ，
      预期的版本为 ${SUPPORTED_KERNEL}
    ##########"
    exit 1
fi
export KERNEL_VERSION="${SUPPORTED_KERNEL}"
echo "KERNEL_VERSION=${SUPPORTED_KERNEL}" | tee -a "$GITHUB_ENV" 
# 移除 SNAPSHOT 标签
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
# Nginx
sed -i "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -ri "/luci-webui.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
sed -ri "/luci-cgi_io.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations
sed -i '1i\log_not_found off;' feeds/packages/net/nginx/files-luci-support/luci.locations
# uwsgi
sed -i 's,procd_set_param stderr 1,procd_set_param stderr 0,g' feeds/packages/net/uwsgi/files/uwsgi.init
sed -i 's,buffer-size = 10000,buffer-size = 131072,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's,logger = luci,#logger = luci,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# rpcd
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

### FW4 ###
rm -rf ./package/network/config/firewall4
cp -rf ../openwrt_ma/package/network/config/firewall4 ./package/network/config/firewall4

### 必要的 Patches ###
# Patch arm64 型号名称
cp -rf ../PATCH/kernel/arm/* ./target/linux/generic/hack-${KERNEL_VERSION}/
# BBRv3
cp -rf ../PATCH/kernel/bbr3/* ./target/linux/generic/backport-${KERNEL_VERSION}/
# LRNG
cp -rf ../PATCH/kernel/lrng/* ./target/linux/generic/hack-${KERNEL_VERSION}/
echo '
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
CONFIG_LRNG_SELFTEST=y
# CONFIG_LRNG_SELFTEST_PANIC is not set
' >>./target/linux/generic/config-${KERNEL_VERSION}
# NETKIT
echo '
CONFIG_NETKIT=y
CONFIG_IPV6_MULTIPLE_TABLES=y
' >>./target/linux/generic/config-${KERNEL_VERSION}
# wg
cp -rf ../PATCH/kernel/wg/* ./target/linux/generic/hack-${KERNEL_VERSION}/
# dont wrongly interpret first-time data
echo "net.netfilter.nf_conntrack_tcp_max_retrans=5" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
# OTHERS
cp -rf ../PATCH/kernel/others/* ./target/linux/generic/pending-${KERNEL_VERSION}/
# luci-app-attendedsysupgrade
sed -i '/luci-app-attendedsysupgrade/d' feeds/luci/collections/luci-nginx/Makefile

### Fullcone-NAT 部分 ###
# bcmfullcone
cp -rf ../PATCH/kernel/bcmfullcone/* ./target/linux/generic/hack-${KERNEL_VERSION}/
# set nf_conntrack_expect_max for fullcone
wget -qO - https://github.com/openwrt/openwrt/commit/bbf39d07.patch | patch -p1
echo "net.netfilter.nf_conntrack_helper = 1" >>./package/kernel/linux/files/sysctl-nf-conntrack.conf
# FW4
mkdir -p package/network/config/firewall4/patches
#cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
mkdir -p package/libs/libnftnl/patches
cp -f ../PATCH/pkgs/firewall/libnftnl/*.patch ./package/libs/libnftnl/patches/
sed -i '/PKG_INSTALL:=/iPKG_FIXUP:=autoreconf' package/libs/libnftnl/Makefile
mkdir -p package/network/utils/nftables/patches
cp -f ../PATCH/pkgs/firewall/nftables/*.patch ./package/network/utils/nftables/patches/
# Patch LuCI 以增添 FullCone 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone-.patch
popd

### Shortcut-FE 部分 ###
# Patch Kernel 以支持 Shortcut-FE
cp -rf ../PATCH/kernel/sfe/* ./target/linux/generic/hack-${KERNEL_VERSION}/
cp -rf ../lede/target/linux/generic/pending-${KERNEL_VERSION}/613-netfilter_optional_tcp_window_check.patch ./target/linux/generic/pending-${KERNEL_VERSION}/613-netfilter_optional_tcp_window_check.patch
# Patch LuCI 以增添 Shortcut-FE 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0002-luci-app-firewall-add-shortcut-fe-option.patch
popd

### NAT6 部分 ###
# custom nft command
patch -p1 < ../PATCH/pkgs/firewall/100-openwrt-firewall4-add-custom-nft-command-support.patch
cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
# Patch LuCI 以增添 NAT6 开关
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0003-luci-app-firewall-add-ipv6-nat-option.patch
popd
# Patch LuCI 以支持自定义 nft 规则
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0004-luci-add-firewall-add-custom-nft-rule-support.patch
popd

### natflow 部分 ###
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0005-luci-app-firewall-add-natflow-offload-support.patch
popd

### fullcone6 ###
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0007-luci-app-firewall-add-fullcone6-option-for-nftables-.patch
popd

### Other Kernel Hack 部分 ###
# make olddefconfig
wget -qO - https://github.com/openwrt/openwrt/commit/c21a3570.patch | patch -p1
# igc-fix
cp -rf ../lede/target/linux/x86/patches-${KERNEL_VERSION}/996-intel-igc-i225-i226-disable-eee.patch ./target/linux/x86/patches-${KERNEL_VERSION}/996-intel-igc-i225-i226-disable-eee.patch
# btf
cp -rf ../PATCH/kernel/btf/* ./target/linux/generic/hack-${KERNEL_VERSION}/

### 获取额外的基础软件包 ###
# Disable Mitigations
sed -i 's,rootwait,rootwait mitigations=off,g' target/linux/rockchip/image/default.bootscript
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-efi.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-iso.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-pc.cfg

### ADD PKG 部分 ###
cp -rf ../OpenWrt-Add ./package/new

# 删除 OpenWrt-Add 顶层遗留的旧版 trojan-plus，避免重复
# 保留 package/new/openwrt_helloworld/trojan-plus
# 来源：sbwml/openwrt_helloworld
# QiuSimons 已将 PassWall 中 trojan-plus 默认设为 n，如需使用需手动开启
# 如需启用，可在 config.seed 中加入：
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y
rm -rf ./package/new/trojan-plus

### Default Settings：修正 UPnP 和 ttyd 默认状态 ###
DEFAULT_SETTINGS="./package/new/addition-trans-zh/files/zzz-default-settings"
DEFAULT_SETTINGS_BAK="./package/new/addition-trans-zh/zzz-default-settings.bak"

if [ -f "$DEFAULT_SETTINGS" ]; then
    [ -f "$DEFAULT_SETTINGS_BAK" ] || cp -af "$DEFAULT_SETTINGS" "$DEFAULT_SETTINGS_BAK"

    # UPnP 默认保持关闭
    sed -i "s/uci set upnpd.config.enabled='1'/uci set upnpd.config.enabled='0'/" "$DEFAULT_SETTINGS"

    # ttyd 保持固件原本的自启动状态，不再首次启动时关闭
    sed -i '/\/etc\/init.d\/ttyd disable 2>\/dev\/null/d' "$DEFAULT_SETTINGS"
    sed -i '/\/etc\/init.d\/ttyd stop/d' "$DEFAULT_SETTINGS"
fi

### ttyd：LAN 接口重新配置后自动重启 ###
TTYD_INIT="./feeds/packages/utils/ttyd/files/ttyd.init"

if [ -f "$TTYD_INIT" ] && ! grep -Fq 'procd_add_interface_trigger "interface.*" "lan" /etc/init.d/$NAME restart' "$TTYD_INIT"; then
    sed -i $'/procd_add_reload_trigger "$NAME"/a\\\n\tprocd_add_interface_trigger "interface.*" "lan" /etc/init.d/$NAME restart' "$TTYD_INIT"
fi

### UnblockNeteaseMusic：补回 Node.js 运行依赖 ###
UNM_MAKEFILE="./package/new/luci-app-unblockneteasemusic/Makefile"
UNM_INIT="./package/new/luci-app-unblockneteasemusic/root/etc/init.d/unblockneteasemusic"

if [ -f "$UNM_MAKEFILE" ]; then
    grep -q '+node' "$UNM_MAKEFILE" || sed -i 's/^LUCI_DEPENDS:=+dnsmasq-full \\/LUCI_DEPENDS:=+dnsmasq-full +node \\/' "$UNM_MAKEFILE"
fi

# OpenWrt 25.12 已使用 apk，删除旧版运行时调用 opkg 安装 node 的逻辑
if [ -f "$UNM_INIT" ]; then
    sed -i '/opkg update.*opkg install node/d' "$UNM_INIT"
fi

### MosDNS：保留关键诊断日志并扩充公共查询信息 ###
# 1. query_summary：使用 Warn 门槛保留输出，最终显示为 Info
# 2. debug_print：使用 Warn 门槛保留输出，最终显示为 Info
# 3. 公共查询日志增加实际 ECS 和当前 marks
# 4. cache / upstream / IP / CNAME / TTL 等继续使用上游已有信息
# 5. 上游相关实现发生变化时，只跳过对应本地增强，避免重复修改或错误套用旧补丁

MOSDNS_PATCH_DIR="./package/new/luci-app-mosdns/mosdns/patches"
MOSDNS_QUERY_PATCH="${MOSDNS_PATCH_DIR}/211-feat-add-query-log-support.patch"
MOSDNS_LOCAL_PATCH="${MOSDNS_PATCH_DIR}/999-local-debug-log-enhance.patch"

# 清理旧版本地补丁
rm -f "${MOSDNS_PATCH_DIR}/999-local-query-log-level.patch"
rm -f "${MOSDNS_LOCAL_PATCH}"

MOSDNS_CONTEXT_PATCH=1
MOSDNS_LOG_PATCH=1

# 当前 Query Log 上游补丁不存在时，无法确认依赖结构
if [ ! -f "${MOSDNS_QUERY_PATCH}" ]; then
	echo "MosDNS: upstream query log patch not found, skip local debug log enhancement"
	MOSDNS_CONTEXT_PATCH=0
	MOSDNS_LOG_PATCH=0
fi

# ECS / marks 已由上游实现时，不再重复增加
if [ "${MOSDNS_CONTEXT_PATCH}" = "1" ] && \
	grep -RqsE 'encoder\.AddString\("ecs"|encoder\.AddArray\("marks"' "${MOSDNS_PATCH_DIR}"; then

	echo "MosDNS: upstream already contains ECS/marks query logging, skip local query context enhancement"
	MOSDNS_CONTEXT_PATCH=0
fi

# 确认本地 ECS / marks 修改依赖的公共 Query Context 结构仍然存在
if [ "${MOSDNS_CONTEXT_PATCH}" = "1" ]; then
	if grep -q 'encoder.AddString("protocol", proto)' "${MOSDNS_QUERY_PATCH}" \
		&& grep -q 'encoder.AddObject("cache"' "${MOSDNS_QUERY_PATCH}" \
		&& grep -q 'ctx.UpstreamSelected != nil' "${MOSDNS_QUERY_PATCH}" \
		&& grep -q 'mlog.IsDebug() && len(ctx.RuleHits) > 0' "${MOSDNS_QUERY_PATCH}"; then

		echo "MosDNS: detected known upstream query context logging"
	else
		echo "MosDNS: upstream query context logging changed, skip local query context enhancement"
		MOSDNS_CONTEXT_PATCH=0
	fi
fi

# 如果 sbw 后续补丁已经修改 query_summary / debug_print，
# 停止自动修改这两个插件，避免重复处理或和新的上游实现冲突
if [ "${MOSDNS_LOG_PATCH}" = "1" ] && \
	grep -RqsE 'plugin/executable/(query_summary/query_summary\.go|debug_print/print\.go)' "${MOSDNS_PATCH_DIR}"; then

	echo "MosDNS: upstream modifies query_summary/debug_print, skip local log level enhancement"
	MOSDNS_LOG_PATCH=0
fi

# 创建本地补丁
if [ "${MOSDNS_CONTEXT_PATCH}" = "1" ] || [ "${MOSDNS_LOG_PATCH}" = "1" ]; then

	: > "${MOSDNS_LOCAL_PATCH}"

	# 公共 Query Context 增加 ECS 和排序后的 marks
	if [ "${MOSDNS_CONTEXT_PATCH}" = "1" ]; then
		cat >> "${MOSDNS_LOCAL_PATCH}" <<'EOF'
--- a/pkg/query_context/context.go
+++ b/pkg/query_context/context.go
@@ -20,5 +20,6 @@
 import (
 	"fmt"
+	"sort"
 	"sync/atomic"
 	"time"
 
@@ -314,3 +315,26 @@
 	encoder.AddString("protocol", proto)
 
+	for _, option := range ctx.QOpt().Option {
+		if ecs, ok := option.(*dns.EDNS0_SUBNET); ok {
+			encoder.AddString("ecs", fmt.Sprintf("%s/%d", ecs.Address.String(), ecs.SourceNetmask))
+			break
+		}
+	}
+
+	if len(ctx.marks) > 0 {
+		marks := make([]uint32, 0, len(ctx.marks))
+		for mark := range ctx.marks {
+			marks = append(marks, mark)
+		}
+		sort.Slice(marks, func(i, j int) bool {
+			return marks[i] < marks[j]
+		})
+		encoder.AddArray("marks", zapcore.ArrayMarshalerFunc(func(arr zapcore.ArrayEncoder) error {
+			for _, mark := range marks {
+				arr.AppendUint32(mark)
+			}
+			return nil
+		}))
+	}
+
 	if mlog.IsDebug() && len(ctx.RuleHits) > 0 {
EOF
	fi

	# query_summary / debug_print：
	# 使用 Warn 级别参与日志门槛判断，通过后将最终显示级别恢复为 Info
	if [ "${MOSDNS_LOG_PATCH}" = "1" ]; then
		cat >> "${MOSDNS_LOCAL_PATCH}" <<'EOF'
--- a/plugin/executable/query_summary/query_summary.go
+++ b/plugin/executable/query_summary/query_summary.go
@@ -62,9 +62,11 @@
 func (l *SummaryLogger) Exec(ctx context.Context, qCtx *query_context.Context, next sequence.ChainWalker) error {
 	err := next.ExecNext(ctx, qCtx)
-	l.l.Info(
-		l.msg,
-		zap.Inline(qCtx),
-		zap.Error(err),
-	)
+	if ce := l.l.Check(zap.WarnLevel, l.msg); ce != nil {
+		ce.Entry.Level = zap.InfoLevel
+		ce.Write(
+			zap.Inline(qCtx),
+			zap.Error(err),
+		)
+	}
 	return err
 }
--- a/plugin/executable/debug_print/print.go
+++ b/plugin/executable/debug_print/print.go
@@ -51,7 +51,16 @@
 func (b *DebugPrint) Exec(_ context.Context, qCtx *query_context.Context) error {
-	b.BQ.L().Info(b.msg, zap.Stringer("query", qCtx.Q()))
+	l := b.BQ.L()
+
+	if ce := l.Check(zap.WarnLevel, b.msg); ce != nil {
+		ce.Entry.Level = zap.InfoLevel
+		ce.Write(zap.Stringer("query", qCtx.Q()))
+	}
+
 	if r := qCtx.R(); r != nil {
-		b.BQ.L().Info(b.msg, zap.Stringer("response", r))
+		if ce := l.Check(zap.WarnLevel, b.msg); ce != nil {
+			ce.Entry.Level = zap.InfoLevel
+			ce.Write(zap.Stringer("response", r))
+		}
 	}
 	return nil
 }
EOF
	fi

	echo "MosDNS: created ${MOSDNS_LOCAL_PATCH}"

	if [ "${MOSDNS_CONTEXT_PATCH}" = "1" ]; then
		echo "MosDNS: query context -> add ECS and sorted marks"
	else
		echo "MosDNS: query context -> keep upstream behavior"
	fi

	if [ "${MOSDNS_LOG_PATCH}" = "1" ]; then
		echo "MosDNS: query_summary -> Warn threshold / Info display"
		echo "MosDNS: debug_print -> Warn threshold / Info display"
	else
		echo "MosDNS: query_summary/debug_print -> keep upstream behavior"
	fi
else
	rm -f "${MOSDNS_LOCAL_PATCH}"
	echo "MosDNS: no local debug log enhancement required"
fi

### OpenAppFilter：切换到 destan19 源码 ###
rm -rf ./package/new/OpenAppFilter
cp -rf ../OpenAppFilter ./package/new/OpenAppFilter

### OpenAppFilter：运行环境兼容修复 ###

OAF_DASHBOARD="./package/new/OpenAppFilter/luci-app-oaf/luasrc/view/oaf/dashboard.htm"
OAF_UBUS_SRC="./package/new/OpenAppFilter/open-app-filter/src/fwx_ubus.c"


### 1. 修复打开 OAF Dashboard 后 自动切菜单样式 ###
# OAF Dashboard 会主动写入：
# localStorage.setItem('luci-menu-category', 'basic');
#
# 这会覆盖 KuCat 已保存的 allmenu 状态，
# 导致进入 OAF 页面后从“完整菜单”自动切回“自定义菜单”。
#
# 仅在该旧代码精确出现 1 次时删除。
# 如果上游已经修复或代码结构发生变化，则自动跳过。

if [ -f "${OAF_DASHBOARD}" ]; then

	OAF_KUCAT_OLD="localStorage.setItem('luci-menu-category', 'basic');"
	OAF_KUCAT_OLD_COUNT="$(grep -Fc "${OAF_KUCAT_OLD}" "${OAF_DASHBOARD}")"

	if [ "${OAF_KUCAT_OLD_COUNT}" -eq 1 ]; then
		echo "OpenAppFilter: fix Dashboard forcing KuCat custom menu"

		sed -i \
			"/localStorage.setItem('luci-menu-category', 'basic');/d" \
			"${OAF_DASHBOARD}"

	elif [ "${OAF_KUCAT_OLD_COUNT}" -eq 0 ]; then
		echo "OpenAppFilter: KuCat target code not found, skip"

	else
		echo "OpenAppFilter: unexpected KuCat menu code count ${OAF_KUCAT_OLD_COUNT}, skip"
	fi

else
	echo "OpenAppFilter: dashboard.htm not found, skip KuCat menu fix"
fi


### 2. 修复 oafd 后台调用 top 报错及多核 CPU 解析兼容 ###
# 原代码：
# top -n 1 | grep 'CPU:' ...
#
# 在 当前 procps-ng 环境存在两个问题：
#
# 1. oafd 由 procd 后台运行，没有 TTY，
#    top -n 1 会持续输出：
#    top: failed tty get
#
# 2. procps-ng 多核 CPU 输出为：
#    %Cpu0
#    %Cpu1
#    ...
#    原来的 grep 'CPU:' 无法正确取得 idle。
#
# 已在实际运行环境验证：
# 使用 top -b -n 1 后无 TTY 报错消失，
# 对所有 %Cpu 行的第 9 列 idle 求平均后，
# 可继续兼容上游现有的：
# cpu_usage = 100 - atoi(result);
#
# 仅在当前已确认的问题代码精确出现 1 次时修改。
# 如果上游已经修复或实现发生变化，则自动跳过。

if [ -f "${OAF_UBUS_SRC}" ]; then

	OAF_CPU_OLD="top -n 1 | grep 'CPU:' | awk -F '%' '{print\$4}' | awk -F ' ' '{print\$2}'"
	OAF_CPU_NEW="LC_ALL=C top -b -n 1 | awk '/^%Cpu/{for(i=2;i<=NF;i++) if(\$i ~ /^id,?\$/){s+=\$(i-1);n++}} END{if(n) print s/n; else print 100}'"

	OAF_CPU_OLD_COUNT="$(grep -Fc "${OAF_CPU_OLD}" "${OAF_UBUS_SRC}")"

	if [ "${OAF_CPU_OLD_COUNT}" -eq 1 ]; then
		echo "OpenAppFilter: fix oafd procps-ng top compatibility"

		sed -i \
			"s@top -n 1 | grep 'CPU:' | awk -F '%' '{print\$4}' | awk -F ' ' '{print\$2}'@LC_ALL=C top -b -n 1 | awk '/^%Cpu/{for(i=2;i<=NF;i++) if(\$i ~ /^id,?\$/){s+=\$(i-1);n++}} END{if(n) print s/n; else print 100}'@" \
			"${OAF_UBUS_SRC}"

	elif grep -Fq "${OAF_CPU_NEW}" "${OAF_UBUS_SRC}"; then
		echo "OpenAppFilter: oafd top compatibility fix already applied"

	elif [ "${OAF_CPU_OLD_COUNT}" -eq 0 ]; then
		echo "OpenAppFilter: CPU target code not found or already changed, skip"

	else
		echo "OpenAppFilter: unexpected CPU command count ${OAF_CPU_OLD_COUNT}, skip"
	fi

else
	echo "OpenAppFilter: fwx_ubus.c not found, skip CPU compatibility fix"
fi


### OpenAppFilter 兼容修复结果检查 ###

echo "===== OpenAppFilter YAOF compatibility patch ====="

if [ -f "${OAF_DASHBOARD}" ]; then
	if grep -Fq "localStorage.setItem('luci-menu-category', 'basic');" "${OAF_DASHBOARD}"; then
		echo "KuCat menu compatibility: NOT PATCHED"
	else
		echo "KuCat menu compatibility: OK"
	fi
fi

if [ -f "${OAF_UBUS_SRC}" ]; then
	if grep -Fq "${OAF_CPU_NEW}" "${OAF_UBUS_SRC}"; then
		echo "oafd top compatibility: OK"
		grep -n -F "${OAF_CPU_NEW}" "${OAF_UBUS_SRC}" || true
	else
		echo "oafd top compatibility: upstream changed or patch skipped"
	fi
fi

### OpenAppFilter：修复异常 skb 长度导致超大内存申请 ###
# 1. 非线性 skb 处理前增加 l4_len > 0 检查
# 2. read_skb 增加 from / len 最终边界检查
# 3. 网络 softirq 路径内存申请改用 GFP_ATOMIC
# 4. 兼容 sbwml v6 的 app_filter.c 和 destan19 新版的 fwx_main.c

OAF_SRC=""
OAF_CAN_PATCH=1

# 优先识别 destan19 新版源码
if [ -f "./package/new/OpenAppFilter/oaf/src/fwx_main.c" ]; then
	OAF_SRC="./package/new/OpenAppFilter/oaf/src/fwx_main.c"

# 兼容 sbwml v6 当前源码
elif [ -f "./package/new/OpenAppFilter/oaf/src/app_filter.c" ]; then
	OAF_SRC="./package/new/OpenAppFilter/oaf/src/app_filter.c"

else
	echo "OpenAppFilter: source file not found, skip safety patch"
	OAF_CAN_PATCH=0
fi

### 1. 修复 l4_len 负数进入 read_skb ###
if [ "${OAF_CAN_PATCH}" = "1" ]; then

	OAF_OLD_COND='if (skb_is_nonlinear(skb) && flow.l4_len < MAX_AF_SUPPORT_DATA_LEN)'
	OAF_NEW_COND='if (skb_is_nonlinear(skb) && flow.l4_len > 0 && flow.l4_len < MAX_AF_SUPPORT_DATA_LEN)'

	# 仍存在旧代码时全部修复
	if grep -Fq "${OAF_OLD_COND}" "${OAF_SRC}"; then
		echo "OpenAppFilter: add l4_len > 0 check"

		sed -i \
			's/if (skb_is_nonlinear(skb) && flow\.l4_len < MAX_AF_SUPPORT_DATA_LEN)/if (skb_is_nonlinear(skb) \&\& flow.l4_len > 0 \&\& flow.l4_len < MAX_AF_SUPPORT_DATA_LEN)/g' \
			"${OAF_SRC}"

	# 已经全部采用安全条件时不重复修改
	elif grep -Fq "${OAF_NEW_COND}" "${OAF_SRC}"; then
		echo "OpenAppFilter: upstream already has l4_len > 0 check"

	else
		echo "OpenAppFilter: l4_len code structure changed, skip this patch"
	fi
fi

### 2. 给 read_skb 增加最终边界检查 ###
if [ "${OAF_CAN_PATCH}" = "1" ]; then

	# 上游已经存在相同或等效边界检查时不重复添加
	if grep -Fq "len > skb->len - from" "${OAF_SRC}"; then
		echo "OpenAppFilter: upstream already has read_skb bounds check"

	else
		OAF_CONSUMED_COUNT="$(grep -Ec '^[[:space:]]*unsigned int consumed = 0;' "${OAF_SRC}")"

		if [ "${OAF_CONSUMED_COUNT}" -eq 1 ]; then
			echo "OpenAppFilter: add read_skb bounds check"

			sed -i $'/^[[:space:]]*unsigned int consumed = 0;/a\\\n\\\n\tif (!skb || !len || len > MAX_AF_SUPPORT_DATA_LEN)\\\n\t\treturn NULL;\\\n\\\n\tif (from >= skb->len || len > skb->len - from)\\\n\t\treturn NULL;' \
				"${OAF_SRC}"

		else
			echo "OpenAppFilter: read_skb structure changed, skip bounds patch"
		fi
	fi
fi

### 3. read_skb 网络 softirq 路径使用 GFP_ATOMIC ###
if [ "${OAF_CAN_PATCH}" = "1" ]; then

	if grep -Fq "msg_buf = kmalloc(len, GFP_ATOMIC);" "${OAF_SRC}"; then
		echo "OpenAppFilter: upstream already uses GFP_ATOMIC"

	else
		OAF_GFP_COUNT="$(grep -Fc "msg_buf = kmalloc(len, GFP_KERNEL);" "${OAF_SRC}")"

		if [ "${OAF_GFP_COUNT}" -eq 1 ]; then
			echo "OpenAppFilter: change read_skb GFP_KERNEL to GFP_ATOMIC"

			sed -i \
				's/msg_buf = kmalloc(len, GFP_KERNEL);/msg_buf = kmalloc(len, GFP_ATOMIC);/' \
				"${OAF_SRC}"

		else
			echo "OpenAppFilter: kmalloc code structure changed, skip GFP patch"
		fi
	fi
fi

### OpenAppFilter 修改结果检查 ###
if [ "${OAF_CAN_PATCH}" = "1" ]; then
	echo "===== OpenAppFilter safety patch ====="
	echo "Source: ${OAF_SRC}"

	echo "===== l4_len checks ====="
	grep -n \
		"skb_is_nonlinear(skb).*flow.l4_len" \
		"${OAF_SRC}" || true

	echo "===== read_skb ====="
	grep -n -A18 \
		"static unsigned char \*read_skb" \
		"${OAF_SRC}" || true
fi

# 添加自定义第三方包
# OpenWrt-Custom 由 01_get_ready.sh 克隆生成
cp -rf ../OpenWrt-Custom ./package/custom

rm -rf package/new/openwrt_pkgs/{luci-app-netdata,luci-app-netspeedtest,luci-app-adguardhome}

rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,frp,microsocks,shadowsocks-libev,zerotier,daed,smartdns,adguardhome}
rm -rf feeds/luci/applications/{luci-app-frps,luci-app-frpc,luci-app-zerotier,luci-app-filemanager,luci-app-smartdns,luci-app-adguardhome}
rm -rf feeds/packages/utils/coremark
sed -i 's/+@KERNEL_DEBUG_INFO_BTF/+vmlinux-btf/' ./package/new/openwrt-einat-ebpf/Makefile
git clone https://github.com/QiuSimons/vmlinux-btf ./package/new/vmlinux-btf


# Q DNS Client
rm -rf ./feeds/packages/net/q
cp -rf ../immortalwrt_pkg_25/net/q ./feeds/packages/net/q

### AdGuardHome ###
# 使用 ImmortalWrt openwrt-25.12 的 AdGuardHome 核心和 LuCI
# cp -rf ../immortalwrt_pkg_25/net/adguardhome ./feeds/packages/net/adguardhome
# cp -rf ../immortalwrt_luci_25/applications/luci-app-adguardhome ./feeds/luci/applications/luci-app-adguardhome

### SmartDNS ###
# 使用 ImmortalWrt openwrt-25.12 的 smartdns / luci-app-smartdns
cp -rf ../immortalwrt_pkg_25/net/smartdns ./feeds/packages/net/smartdns
cp -rf ../immortalwrt_luci_25/applications/luci-app-smartdns ./feeds/luci/applications/luci-app-smartdns
# SmartDNS WebUI 编译依赖
rm -rf ./feeds/packages/devel/rust-bindgen
mkdir -p ./feeds/packages/devel
cp -rf ../immortalwrt_pkg_25/devel/rust-bindgen  ./feeds/packages/devel/rust-bindgen

SEED_NAME="${seed:-X86}"
SEED_FILE="../SEED/${SEED_NAME}/config.seed"

### AdvancedPlus：默认关闭 ZSH 后台菜单 ###
if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-advancedplus=y" "$SEED_FILE"; then
    ADVANCEDPLUS_CONFIG="./package/custom/luci-app-advancedplus/root/etc/config/advancedplus"
    ADVANCEDPLUS_CONFIG_BAK="./package/custom/luci-app-advancedplus/advancedplus.bak"
    [ -f "$ADVANCEDPLUS_CONFIG_BAK" ] || cp -af "$ADVANCEDPLUS_CONFIG" "$ADVANCEDPLUS_CONFIG_BAK"
    sed -i '/^[[:space:]]*option usshmenu/d' "$ADVANCEDPLUS_CONFIG"
    sed -i "/^config basic/a\\$(printf '\t')option usshmenu '1'" "$ADVANCEDPLUS_CONFIG"
fi

### TaskPlan：保存配置后自动刷新定时任务 ###
if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-taskplan=y" "$SEED_FILE"; then
    TASKPLAN_UCITRACK="./package/new/luci-app-taskplan/luci-app-taskplan/root/usr/share/ucitrack/luci-app-taskplan.json"
    mkdir -p "$(dirname "$TASKPLAN_UCITRACK")"
    cat > "$TASKPLAN_UCITRACK" <<'EOF'
{
	"config": "taskplan",
	"exec": "/etc/init.d/taskplan start"
}
EOF
fi

### KuCat Config：补充 kucat-config RPCD 执行权限 ###
if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-kucat-config=y" "$SEED_FILE"; then
    KUCAT_ACL="./package/custom/luci-app-kucat-config/root/usr/share/rpcd/acl.d/luci-app-kucat-config.json"
    KUCAT_ACL_BAK="./package/custom/luci-app-kucat-config/luci-app-kucat-config.json.bak"
    [ -f "$KUCAT_ACL_BAK" ] || cp -af "$KUCAT_ACL" "$KUCAT_ACL_BAK"
    grep -q '"/usr/bin/kucat-config"' "$KUCAT_ACL" || sed -i 's#^\([[:space:]]*\)"/etc/init.d/kucat": \[ "exec" \],#\1"/etc/init.d/kucat": [ "exec" ],\n\1"/usr/bin/kucat-config": [ "exec" ],#' "$KUCAT_ACL"
fi

### KuCat Theme：默认显示完整菜单 ###
if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-theme-kucat=y" "$SEED_FILE"; then
    KUCAT_MENU="./package/custom/luci-theme-kucat/htdocs/luci-static/resources/menu-kucat.js"
    KUCAT_MENU_BAK="./package/custom/luci-theme-kucat/menu-kucat.js.bak"
    [ -f "$KUCAT_MENU_BAK" ] || cp -af "$KUCAT_MENU" "$KUCAT_MENU_BAK"
    sed -i "s/currentCategory: 'basic'/currentCategory: 'allmenu'/" "$KUCAT_MENU"
fi

### WechatPush：补充新版 rpcd 的 /proc/net/arp 真实路径读取权限 ###
### 上游已于 2026-08 改用 luci-rpc getHostHints，暂时停用本地兼容，保留代码便于回溯
: <<'WECHATPUSH_ARP_UPSTREAM_FIXED'

if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-wechatpush=y" "$SEED_FILE"; then
    WECHATPUSH_ACL="./package/new/luci-app-wechatpush/root/usr/share/rpcd/acl.d/luci-app-wechatpush.json"
    WECHATPUSH_ACL_BAK="./package/new/luci-app-wechatpush/luci-app-wechatpush.json.bak"
    [ -f "$WECHATPUSH_ACL_BAK" ] || cp -af "$WECHATPUSH_ACL" "$WECHATPUSH_ACL_BAK"
    grep -q '"/proc/\*/net/arp"' "$WECHATPUSH_ACL" || sed -i '/"\/proc\/net\/arp": \[ "read" \],/a\				"/proc/*/net/arp": [ "read" ],' "$WECHATPUSH_ACL"
fi

WECHATPUSH_ARP_UPSTREAM_FIXED

### WechatPush：修复温度测试失败后进入主循环 ###
if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-wechatpush=y" "$SEED_FILE"; then
    WECHATPUSH_SCRIPT="./package/new/luci-app-wechatpush/root/usr/share/wechatpush/wechatpush"
    WECHATPUSH_SCRIPT_BAK="./package/new/luci-app-wechatpush/wechatpush.bak"

    if [ -f "$WECHATPUSH_SCRIPT" ]; then
        [ -f "$WECHATPUSH_SCRIPT_BAK" ] || cp -af "$WECHATPUSH_SCRIPT" "$WECHATPUSH_SCRIPT_BAK"

        if grep -Eq '^[[:space:]]*soc_temp[[:space:]]*&&[[:space:]]*exit[[:space:]]+\$\?[[:space:]]*$' "$WECHATPUSH_SCRIPT"; then
            sed -Ei 's/^([[:space:]]*)soc_temp[[:space:]]*&&[[:space:]]*exit[[:space:]]+\$\?[[:space:]]*$/\1soc_temp; exit $?/' "$WECHATPUSH_SCRIPT"
            echo "WechatPush soc loop bug fixed"
        else
            echo "WechatPush soc loop bug not found, skip"
        fi
    fi
fi


### ZeroTier：关闭状态不执行 zerotier-fw4，并补齐 peers.d 目录 ###
if [ -f "$SEED_FILE" ] && grep -Eq "^CONFIG_PACKAGE_(zerotier|luci-app-zerotier)=y" "$SEED_FILE"; then
    ZEROTIER_INIT="./package/new/imm_pkg/zerotier/files/etc/init.d/zerotier"
    ZEROTIER_INIT_BAK="./package/new/imm_pkg/zerotier/zerotier.init.bak"

    if [ -f "$ZEROTIER_INIT" ]; then
        [ -f "$ZEROTIER_INIT_BAK" ] || cp -af "$ZEROTIER_INIT" "$ZEROTIER_INIT_BAK"

        ### 1. 关闭状态不执行 zerotier-fw4 ###
        if grep -q '^service_started() {$' "$ZEROTIER_INIT"; then
            sed -i '/^service_started() {$/,/^}$/c\
service_started() {\
\tlocal enabled\
\tconfig_load zerotier\
\tconfig_get_bool enabled '\''global'\'' '\''enabled'\'' 0\
\t[ "${enabled}" -eq 1 ] || return 0\
\tzerotier-fw4 -s\
}' "$ZEROTIER_INIT"
        fi

        ### 2. 创建 ZeroTier peers.d 目录 ###
        if grep -q '^[[:space:]]*mkdir -p "${CONFIG_PATH}"/networks.d$' "$ZEROTIER_INIT"; then
            sed -i 's#^\([[:space:]]*\)mkdir -p "${CONFIG_PATH}"/networks.d$#\1mkdir -p "${CONFIG_PATH}"/networks.d "${CONFIG_PATH}"/peers.d#' "$ZEROTIER_INIT"
        fi
    fi
fi

### OpenClash 核心和规则预置 ###
# 根据当前平台预置 OpenClash 核心和规则数据库
# 只有当前平台 config.seed 选择 luci-app-openclash 时才执行

OPENCLASH_DIR="package/new/OpenClash/luci-app-openclash/root/etc/openclash"
OPENCLASH_CONFIG="package/new/OpenClash/luci-app-openclash/root/etc/config/openclash"

if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-openclash=y" "$SEED_FILE"; then
    echo "luci-app-openclash is selected in ${SEED_FILE}"

    if [ -d "$OPENCLASH_DIR" ]; then
        echo "Found OpenClash directory: $OPENCLASH_DIR"

        case "$SEED_NAME" in
            X86)
                CORE_META="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v2.tar.gz"
                ;;
            R2C|R2S|R3S|R4S)
                CORE_META="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
                ;;
            *)
                CORE_META=""
                echo "Unknown target ${SEED_NAME}, skip OpenClash core preset"
                ;;
        esac

        mkdir -p "$OPENCLASH_DIR/core"

        curl --retry 3 --connect-timeout 15 -fL -o "$OPENCLASH_DIR/Country.mmdb" \
            "https://github.com/xream/geoip/releases/latest/download/ipinfo.country.mmdb" \
            || echo "Country.mmdb download failed, skip"

        curl --retry 3 --connect-timeout 15 -fL -o "$OPENCLASH_DIR/GeoSite.dat" \
            "https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat" \
            || echo "GeoSite.dat download failed, skip"

        curl --retry 3 --connect-timeout 15 -fL -o "$OPENCLASH_DIR/GeoIP.dat" \
            "https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat" \
            || echo "GeoIP.dat download failed, skip"

        if [ -n "$CORE_META" ]; then
            if curl --retry 3 --connect-timeout 15 -fL -o "$OPENCLASH_DIR/core/meta.tar.gz" "$CORE_META"; then
                tar -zxf "$OPENCLASH_DIR/core/meta.tar.gz" -C "$OPENCLASH_DIR/core"

                if [ -f "$OPENCLASH_DIR/core/clash" ]; then
                    mv -f "$OPENCLASH_DIR/core/clash" "$OPENCLASH_DIR/core/clash_meta"
                    chmod +x "$OPENCLASH_DIR/core/clash_meta"
                    echo "OpenClash meta core preset done"
                else
                    echo "OpenClash meta core extracted, but clash binary not found"
                fi

                rm -f "$OPENCLASH_DIR/core/meta.tar.gz"
            else
                echo "OpenClash meta core download failed, skip core preset"
            fi
        fi

        if [ -f "$OPENCLASH_CONFIG" ]; then
            echo "Found OpenClash config: $OPENCLASH_CONFIG"

            sed -i "s|option geo_custom_url.*|option geo_custom_url 'https://github.com/xream/geoip/releases/latest/download/ipinfo.country.mmdb'|" "$OPENCLASH_CONFIG"
            sed -i "s|option geosite_custom_url.*|option geosite_custom_url 'https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat'|" "$OPENCLASH_CONFIG"
            sed -i "s|option geoip_custom_url.*|option geoip_custom_url 'https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat'|" "$OPENCLASH_CONFIG"
            sed -i "s|option geoasn_custom_url.*|option geoasn_custom_url 'https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb'|" "$OPENCLASH_CONFIG"
            sed -i "s|option chnr_custom_url.*|option chnr_custom_url 'https://github.com/DH-Teams/DH-Geo_AS_IP_CN/raw/main/Geo_AS_IP_CN.txt'|" "$OPENCLASH_CONFIG"
            sed -i "s|option chnr6_custom_url.*|option chnr6_custom_url 'https://raw.githubusercontent.com/DH-Teams/DH-Geo_AS_IP_CN/main/Geo_AS_IP_CN_6.txt'|" "$OPENCLASH_CONFIG"
            # sed -i "s|option chnr_custom_url.*|option chnr_custom_url 'https://us.cooluc.com/cidr/cn_ipv4.cidr'|" "$OPENCLASH_CONFIG"
            # sed -i "s|option chnr6_custom_url.*|option chnr6_custom_url 'https://us.cooluc.com/cidr/cn_ipv6.cidr'|" "$OPENCLASH_CONFIG"
            echo "OpenClash default URLs patched"
        else
            echo "OpenClash config file not found: $OPENCLASH_CONFIG"
        fi
    else
        echo "OpenClash directory not found: $OPENCLASH_DIR"
    fi
else
    echo "luci-app-openclash is not selected in ${SEED_FILE}, skip OpenClash preset"
fi

### PassWall 规则预置 ###
# 只有当前平台 config.seed 选择 luci-app-passwall 时才更新 gfwlist

PASSWALL_GFWLIST="package/new/openwrt_helloworld/luci-app-passwall/root/usr/share/passwall/rules/gfwlist"

if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-passwall=y" "$SEED_FILE"; then
    echo "luci-app-passwall is selected in ${SEED_FILE}"

    if [ -d "$(dirname "$PASSWALL_GFWLIST")" ]; then
        curl --retry 3 --connect-timeout 15 -fL -o "$PASSWALL_GFWLIST" \
            "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt" \
            || echo "PassWall gfwlist download failed, skip"
    else
        echo "PassWall rules directory not found: $(dirname "$PASSWALL_GFWLIST")"
    fi
else
    echo "luci-app-passwall is not selected in ${SEED_FILE}, skip PassWall gfwlist"
fi

### WeChatPush Logo 预置 ###
# 只有当前平台 config.seed 选择 luci-app-wechatpush 时才替换 通知logo

WECHATPUSH_LOGO="package/new/luci-app-wechatpush/root/usr/share/wechatpush/api/logo.jpg"

if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_luci-app-wechatpush=y" "$SEED_FILE"; then
    echo "luci-app-wechatpush is selected in ${SEED_FILE}"

    if [ -d "$(dirname "$WECHATPUSH_LOGO")" ]; then
        curl --retry 3 --connect-timeout 15 -fL -o "$WECHATPUSH_LOGO" \
            "https://raw.githubusercontent.com/lonecale/Groceries/main/Logo/logo.jpg" \
            || echo "WeChatPush logo download failed, skip"
    else
        echo "WeChatPush logo directory not found: $(dirname "$WECHATPUSH_LOGO")"
    fi
else
    echo "luci-app-wechatpush is not selected in ${SEED_FILE}, skip WeChatPush logo"
fi

### procps-ng top 默认配置预置 ###

TOP_DEFAULT_RC="package/base-files/files/etc/topdefaultrc"

if [ -f "$SEED_FILE" ] && grep -q "^CONFIG_PACKAGE_procps-ng-top=y" "$SEED_FILE"; then
    echo "procps-ng-top is selected in ${SEED_FILE}"

    if [ -d "$(dirname "$TOP_DEFAULT_RC")" ]; then
        curl --retry 3 --connect-timeout 15 -fL -o "$TOP_DEFAULT_RC" \
            "https://raw.githubusercontent.com/lonecale/Groceries/main/Diy/toprc" \
            || echo "procps-ng top default config download failed, skip"
    else
        echo "top default config directory not found: $(dirname "$TOP_DEFAULT_RC")"
    fi
else
    echo "procps-ng-top is not selected in ${SEED_FILE}, skip top default config"
fi

### 获取额外的 LuCI 应用、主题和依赖 ###
# RK
sed -i '/REQUIRE_IMAGE_METADATA/d' target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh
wget https://github.com/coolsnowwolf/lede/raw/refs/heads/master/target/linux/rockchip/patches-6.12/991-arm64-dts-rockchip-add-more-cpu-operating-points-for.patch -O target/linux/rockchip/patches-6.12/991.patch
wget https://github.com/coolsnowwolf/lede/raw/refs/heads/master/target/linux/rockchip/patches-6.12/992-rockchip-rk3399-overclock-to-2.2-1.8-GHz.patch -O target/linux/rockchip/patches-6.12/992.patch
# 更换 Nodejs 版本
rm -rf ./feeds/packages/lang/node
rm -rf ./package/new/feeds_packages_lang_node-prebuilt
cp -rf ../OpenWrt-Add/feeds_packages_lang_node-prebuilt ./feeds/packages/lang/node
# 更换 golang 版本
rm -rf ./feeds/packages/lang/golang
cp -rf ../openwrt_pkg_ma/lang/golang ./feeds/packages/lang/golang
#git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
# apk
pushd feeds/luci
wget -qO- https://github.com/sbwml/r4s_build_script/raw/refs/heads/master/openwrt/patch/luci/applications/luci-app-package-manager/0001-luci-app-package-manager-support-installing-uploaded.patch | patch -p1
popd
# rust
wget https://github.com/rust-lang/rust/commit/cdae267.patch -O feeds/packages/lang/rust/patches/cdae267.patch
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
# mount cgroupv2
pushd feeds/packages
#patch -p1 <../../../PATCH/pkgs/cgroupfs-mount/0001-fix-cgroupfs-mount.patch
popd
mkdir -p feeds/packages/utils/cgroupfs-mount/patches
cp -rf ../PATCH/pkgs/cgroupfs-mount/900-mount-cgroup-v2-hierarchy-to-sys-fs-cgroup-cgroup2.patch ./feeds/packages/utils/cgroupfs-mount/patches/
cp -rf ../PATCH/pkgs/cgroupfs-mount/901-fix-cgroupfs-umount.patch ./feeds/packages/utils/cgroupfs-mount/patches/
cp -rf ../PATCH/pkgs/cgroupfs-mount/902-mount-sys-fs-cgroup-systemd-for-docker-systemd-suppo.patch ./feeds/packages/utils/cgroupfs-mount/patches/
# fstool
wget -qO - https://github.com/coolsnowwolf/lede/commit/8a4db76.patch | patch -p1
# Boost 通用即插即用
rm -rf ./feeds/packages/net/miniupnpd
cp -rf ../openwrt_pkg_ma/net/miniupnpd ./feeds/packages/net/miniupnpd
mkdir -p feeds/packages/net/miniupnpd/patches
wget https://github.com/miniupnp/miniupnp/commit/0e8c68d.patch -O feeds/packages/net/miniupnpd/patches/0e8c68d.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/0e8c68d.patch
wget https://github.com/miniupnp/miniupnp/commit/21541fc.patch -O feeds/packages/net/miniupnpd/patches/21541fc.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/21541fc.patch
wget https://github.com/miniupnp/miniupnp/commit/b78a363.patch -O feeds/packages/net/miniupnpd/patches/b78a363.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/b78a363.patch
wget https://github.com/miniupnp/miniupnp/commit/8f2f392.patch -O feeds/packages/net/miniupnpd/patches/8f2f392.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/8f2f392.patch
wget https://github.com/miniupnp/miniupnp/commit/60f5705.patch -O feeds/packages/net/miniupnpd/patches/60f5705.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/60f5705.patch
wget https://github.com/miniupnp/miniupnp/commit/3f3582b.patch -O feeds/packages/net/miniupnpd/patches/3f3582b.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/3f3582b.patch
wget https://github.com/miniupnp/miniupnp/commit/6aefa9a.patch -O feeds/packages/net/miniupnpd/patches/6aefa9a.patch
sed -i 's,/miniupnpd/,/,g' ./feeds/packages/net/miniupnpd/patches/6aefa9a.patch
pushd feeds/packages
patch -p1 <../../../PATCH/pkgs/miniupnpd/01-set-presentation_url.patch
patch -p1 <../../../PATCH/pkgs/miniupnpd/02-force_forwarding.patch
popd
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/miniupnpd/luci-upnp-support-force_forwarding-flag.patch
popd
# 动态DNS
sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns
# Docker 容器
rm -rf ./feeds/luci/applications/luci-app-dockerman
cp -rf ../dockerman/applications/luci-app-dockerman ./feeds/luci/applications/luci-app-dockerman
sed -i '/auto_start/d' feeds/luci/applications/luci-app-dockerman/root/etc/uci-defaults/luci-app-dockerman
pushd feeds/packages
wget -qO- https://github.com/openwrt/packages/commit/e2e5ee69.patch | patch -p1
wget -qO- https://github.com/openwrt/packages/pull/20054.patch | patch -p1
popd
sed -i '/sysctl.d/d' feeds/packages/utils/dockerd/Makefile
rm -rf ./feeds/luci/collections/luci-lib-docker
cp -rf ../docker_lib/collections/luci-lib-docker ./feeds/luci/collections/luci-lib-docker
# IPv6 兼容助手
patch -p1 <../PATCH/pkgs/odhcp6c/1002-odhcp6c-support-dhcpv6-hotplug.patch
# ODHCPD
rm -rf ./package/network/services/odhcpd
cp -rf ../openwrt_ma/package/network/services/odhcpd ./package/network/services/odhcpd
rm -rf ./package/network/ipv6/odhcp6c
cp -rf ../openwrt_ma/package/network/ipv6/odhcp6c ./package/network/ipv6/odhcp6c
# watchcat
echo > ./feeds/packages/utils/watchcat/files/watchcat.config
# 默认开启 Irqbalance
#sed -i "s/enabled '0'/enabled '1'/g" feeds/packages/utils/irqbalance/files/irqbalance.config

# 使用 TEO CPU 空闲调度器
CONFIG_CONTENT='
CONFIG_CPU_IDLE_GOV_MENU=n
CONFIG_CPU_IDLE_GOV_TEO=y
'
# 查找所有与内核相关的配置文件并将这些配置项追加到文件末尾
find ./target/linux/ -name "config-${KERNEL_VERSION}" | xargs -I{} sh -c "echo '$CONFIG_CONTENT' | tee -a {} > /dev/null"

### 最后的收尾工作 ###
# Lets Fuck
mkdir -p package/base-files/files/usr/bin
cp -rf ../OpenWrt-Add/fuck ./package/base-files/files/usr/bin/fuck
# 生成默认配置及缓存
rm -rf .config
sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-${KERNEL_VERSION}

./scripts/feeds update -i
./scripts/feeds install -a

#exit 0
