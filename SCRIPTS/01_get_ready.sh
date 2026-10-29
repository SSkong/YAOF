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
immortalwrt_pkg_repo="https://github.com/immortalwrt/packages.git"

openwrt_repo="https://github.com/openwrt/openwrt.git"
openwrt_pkg_repo="https://github.com/openwrt/packages.git"
openwrt_add_repo="https://github.com/QiuSimons/OpenWrt-Add.git"

# 开始克隆仓库，并行执行
clone_repo $openwrt_repo $latest_release openwrt &
#clone_repo $openwrt_repo openwrt-25.12 openwrt &
clone_repo $openwrt_repo openwrt-25.12 openwrt_snap &
clone_repo $immortalwrt_pkg_repo master imm_pkg &

clone_repo $openwrt_repo main openwrt_ma &
clone_repo $openwrt_pkg_repo master openwrt_pkg_ma &
clone_repo $openwrt_add_repo master OpenWrt-Add &
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
