#!/bin/bash

# 这个脚本的作用是从不同的仓库中克隆openwrt相关的代码，并进行一些处理

# 定义一个函数，用来克隆指定的仓库和分支
clone_repo() {
  # 参数1是仓库地址，参数2是分支名，参数3是目标目录
  repo_url=$1
  branch_name=$2
  target_dir=$3
  # 克隆仓库到目标目录，并指定分支名和深度为1
  git clone -b $branch_name --depth 1 $repo_url $target_dir
}

# 定义一些变量，存储仓库地址和分支名
latest_release="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/.tar.gz//g')"
immortalwrt_repo="https://github.com/immortalwrt/immortalwrt.git"
immortalwrt_pkg_repo="https://github.com/immortalwrt/packages.git"
immortalwrt_luci_repo="https://github.com/immortalwrt/luci.git"
lede_repo="https://github.com/coolsnowwolf/lede.git"
lede_luci_repo="https://github.com/coolsnowwolf/luci.git"
lede_pkg_repo="https://github.com/coolsnowwolf/packages.git"
openwrt_repo="https://github.com/openwrt/openwrt.git"
openwrt_pkg_repo="https://github.com/openwrt/packages.git"
openwrt_luci_repo="https://github.com/openwrt/luci.git"
lienol_repo="https://github.com/Lienol/openwrt.git"
lienol_pkg_repo="https://github.com/Lienol/openwrt-package"
openwrt_add_repo="https://github.com/QiuSimons/OpenWrt-Add.git"
openwrt_node_repo="https://github.com/nxhack/openwrt-node-packages.git"
passwall_pkg_repo="https://github.com/xiaorouji/openwrt-passwall-packages"
passwall_luci_repo="https://github.com/xiaorouji/openwrt-passwall"
openwrt_third_repo="https://github.com/jjm2473/openwrt-third"
dockerman_repo="https://github.com/lisaac/luci-app-dockerman"
diskman_repo="https://github.com/lisaac/luci-app-diskman"
docker_lib_repo="https://github.com/lisaac/luci-lib-docker"
mosdns_repo="https://github.com/QiuSimons/openwrt-mos"
ssrp_repo="https://github.com/fw876/helloworld"
zxlhhyccc_repo="https://github.com/zxlhhyccc/bf-package-master"
linkease_repo="https://github.com/linkease/openwrt-app-actions"
linkease_pkg_repo="https://github.com/jjm2473/packages"
linkease_luci_repo="https://github.com/jjm2473/luci"

sirpdboy_repo="https://github.com/sirpdboy/sirpdboy-package"
sirpdboy_poweroff_repo="https://github.com/sirpdboy/luci-app-poweroffdevice"
sirpdboy_ddns_go_repo="https://github.com/sirpdboy/luci-app-ddns-go"
sirpdboy_kucat_repo="https://github.com/sirpdboy/luci-theme-kucat"
sirpdboy_kucat_config_repo="https://github.com/sirpdboy/luci-app-kucat-config"
sirpdboy_netwizard_repo="https://github.com/sirpdboy/luci-app-netwizard"
sirpdboy_netdata_repo="https://github.com/sirpdboy/luci-app-netdata"
sirpdboy_advancedplus_repo="https://github.com/sirpdboy/luci-app-advancedplus"
sirpdboy_timecontrol_repo="https://github.com/sirpdboy/luci-app-timecontrol"
sirpdboy_lucky_repo="https://github.com/sirpdboy/luci-app-lucky"
sirpdboy_netspeedtest_repo="https://github.com/sirpdboy/netspeedtest"
sirpdboy_adguardhome_repo="https://github.com/sirpdboy/luci-app-adguardhome"

sbw_quickfile_repo="https://github.com/sbwml/luci-app-quickfile"

sbwdaednext_repo="https://github.com/sbwml/luci-app-daed-next"
lucidaednext_repo="https://github.com/QiuSimons/luci-app-daed-next"
sbwfw876_repo="https://github.com/sbwml/openwrt_helloworld"
sbw_pkg_repo="https://github.com/sbwml/openwrt_pkgs"
natmap_repo="https://github.com/blueberry-pie-11/luci-app-natmap"
xwrt_repo="https://github.com/QiuSimons/openwrt-natflow"

# 开始克隆仓库，并行执行
clone_repo $openwrt_repo $latest_release openwrt &
#clone_repo $openwrt_repo openwrt-25.12 openwrt &
clone_repo $openwrt_repo openwrt-25.12 openwrt_snap &
clone_repo $immortalwrt_repo openwrt-24.10 immortalwrt_24 &
clone_repo $immortalwrt_repo openwrt-23.05 immortalwrt_23 &
clone_repo $lede_repo master lede &
clone_repo $lede_pkg_repo master lede_pkg_ma &
clone_repo $openwrt_repo main openwrt_ma &
clone_repo $openwrt_pkg_repo master openwrt_pkg_ma &
clone_repo $openwrt_add_repo master OpenWrt-Add &
clone_repo $dockerman_repo master dockerman &
clone_repo $docker_lib_repo master docker_lib &

clone_repo $sirpdboy_poweroff_repo master luci-app-poweroffdevice &
clone_repo $sirpdboy_ddns_go_repo main luci-app-ddns-go &
clone_repo $sirpdboy_kucat_repo master luci-theme-kucat &
clone_repo $sirpdboy_kucat_config_repo master luci-app-kucat-config &
clone_repo $sirpdboy_netdata_repo main luci-app-netdata &
clone_repo $sirpdboy_netwizard_repo main luci-app-netwizard &
clone_repo $sirpdboy_advancedplus_repo main luci-app-advancedplus &
clone_repo $sirpdboy_timecontrol_repo main luci-app-timecontrol &
clone_repo $sirpdboy_lucky_repo main luci-app-lucky &
clone_repo $sirpdboy_netspeedtest_repo main netspeedtest &
clone_repo $sirpdboy_adguardhome_repo main luci-app-adguardhome &

clone_repo $sbw_quickfile_repo main luci-app-quickfile &

# 等待所有后台任务完成
wait

# 进行一些处理
cp -rf openwrt_snap/include/package-pack.mk /tmp/package-pack.mk.bak
cp -rf openwrt_snap/include/package.mk /tmp/package.mk.bak
cp -rf openwrt_snap/include/kernel.mk /tmp/kernel.mk.bak
cp -rf openwrt_snap/scripts/metadata.pm /tmp/metadata.pm.bak
cp -rf openwrt/package/libs/toolchain/Makefile /tmp/Makefile.bak
cp -rf openwrt/package/system/procd /tmp/procd.bak
cp -rf openwrt/package/libs/libubox /tmp/libubox.bak
find openwrt/package/* -maxdepth 0 ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' -exec rm -rf {} +
rm -rf ./openwrt/package/base-files/files/lib
cp -rf ./openwrt_snap/package/base-files/files/lib ./openwrt/package/base-files/files/
rm -rf ./openwrt_snap/package/firmware ./openwrt_snap/package/kernel ./openwrt_snap/package/base-files ./openwrt_snap/package/Makefile
cp -rf ./openwrt_snap/package/* ./openwrt/package/
cp -rf /tmp/package-pack.mk.bak ./openwrt/include/package-pack.mk
cp -rf /tmp/package.mk.bak ./openwrt/include/package.mk
cp -rf /tmp/kernel.mk.bak ./openwrt/include/kernel.mk
cp -rf /tmp/metadata.pm.bak ./openwrt/scripts/metadata.pm
cp -rf /tmp/Makefile.bak ./openwrt/package/libs/toolchain/Makefile
cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default
rm -rf openwrt/package/system/procd
cp -rf /tmp/procd.bak ./openwrt/package/system/procd
rm -rf openwrt/package/libs/libubox
cp -rf /tmp/libubox.bak ./openwrt/package/libs/libubox

# 退出脚本
exit 0
