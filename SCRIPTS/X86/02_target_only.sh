#!/bin/bash

#sed -i 's/O2/O2 -march=x86-64-v2/g' include/target.mk

# libsodium
sed -i 's,no-mips16 no-lto,no-mips16,g' feeds/packages/libs/libsodium/Makefile

echo '#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

if grep -q "Default string" /tmp/sysinfo/model 2>/dev/null; then
    echo "Generic PC" > /tmp/sysinfo/model
fi

PSTATE_STATUS_FILE="/sys/devices/system/cpu/intel_pstate/status"
if [ -f "$PSTATE_STATUS_FILE" ]; then
    if [ "$(cat "$PSTATE_STATUS_FILE")" = "passive" ]; then
        echo "active" > "$PSTATE_STATUS_FILE"
    fi
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu_gov" ] && echo "powersave" > "$cpu_gov"
    done
    for cpu_epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -f "$cpu_epp" ] && echo "balance_performance" > "$cpu_epp"
    done
fi

exit 0
' > ./package/base-files/files/etc/rc.local

#Vermagic
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/x86/64/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

### X86 默认设置 ###
# 生成首次启动执行的 uci-defaults 脚本

DEFAULT_SETTINGS="./files/etc/uci-defaults/99-x86-defaults"
mkdir -p "$(dirname "$DEFAULT_SETTINGS")"

cat > "$DEFAULT_SETTINGS" <<'EOF'
#!/bin/sh

### 主机名 ###
uci -q set system.@system[0].hostname='EZwrt'
uci -q commit system
echo 'EZwrt' > /proc/sys/kernel/hostname 2>/dev/null || true

### 默认主题 ###
uci -q set luci.main.mediaurlbase='/luci-static/kucat'
uci -q commit luci

### 主机名映射 ###
# 解决安卓原生TV首次连不上网的问题
uci -q add dhcp domain
uci -q set dhcp.@domain[-1].name='time.android.com'
uci -q set dhcp.@domain[-1].ip='203.107.6.88'

### DHCP 设置 ###
# 旁路网关模式：主路由负责 DHCP，本机不提供 DHCP 服务
#uci -q set dhcp.lan.ignore='1'
#uci -q set dhcp.lan.dhcpv4='disabled'
# 禁用动态分配，只允许静态租约
#uci -q set dhcp.lan.dynamicdhcp='0'


# 关闭 IPv6 RA、DHCPv6、NDP，避免本机在 LAN 侧下发 IPv6 配置
#uci -q delete dhcp.lan.ra
#uci -q delete dhcp.lan.dhcpv6
#uci -q delete dhcp.lan.ra_management
#uci -q delete dhcp.lan.ndp

#uci -q commit dhcp

### 网络设置 ###
# 旁路网关模式：本机默认网关和 DNS 指向主路由
#uci -q set network.lan.gateway='10.0.0.2'

#uci -q delete network.lan.dns
#uci -q add_list network.lan.dns='10.0.0.2'

# 关闭 LAN 口 IPv6 前缀委托和 IPv6 分配
#uci -q set network.lan.delegate='0'
#uci -q delete network.lan.ip6assign
#uci -q set network.lan.ip6ifaceid='eui64'

# 旁路网关不使用默认 WAN
#uci -q delete network.wan
#uci -q delete network.wan6

#uci -q commit network

exit 0
EOF

chmod 755 "$DEFAULT_SETTINGS"

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

exit 0
