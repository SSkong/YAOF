#!/bin/bash
clear

# H68K: 2.5GbE (RTL8125B) 使用主线 kmod-r8169 即可，无需替换 r8168
# 使用特定的优化
#sed -i 's,-mcpu=generic,-march=armv8-a+crc+crypto,g' include/target.mk

# === H68K backport: OpenWrt PR #21270 (rockchip: add HINLINK H66K / H68K support) ===
# PR 合并于 2026-01-24 (main)，未进入 v25.12.x release，此处 backport 到 25.12 (kernel 6.12)
# 涉及 9 个文件：uboot-rockchip Makefile+106 patch、armv8.mk、board.d(01_leds/02_network)、
# hotplug.d/40-net-smp-affinity、patches-6.12 (073-1/073-2/121)
if [ -f ./backport/h68k-backport.patch ]; then
    echo "Applying H68K backport patch (openwrt#21270)..."
    patch -p1 --force --no-backup-if-mismatch < ./backport/h68k-backport.patch || {
        echo "ERROR: H68K backport patch failed, aborting."
        exit 1
    }
else
    echo "ERROR: ./backport/h68k-backport.patch not found, cannot enable H68K support."
    exit 1
fi

#Vermagic
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/rockchip/armv8/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

#exit 0
