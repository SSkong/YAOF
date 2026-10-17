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

# RK3568 PCIe3 PHY SRAM 固件加载补丁（来源 FriendlyElec 内核 unifreq/linux-6.12.y，fw-d54d0eb）
# 修复：部分 H68K（2022 旧版）上 PCIe3 PHY 内部 SRAM 自动加载永不完成，
# 报 "rockchip_p3phy_rk3568_init: lock failed 0x6890000, check input refclk and power supply"，
# pcie3x1/pcie3x2 probe -110 超时 → eth2/eth3（RTL8125B）缺失。
# 供电与参考时钟均已验证正常，此为 PHY 硬件批次特性：需手动上传 SRAM 固件。
if [ -f ./backport/105-phy-rockchip-snps-pcie3-sram-firmware.patch ]; then
    echo "Installing RK3568 PCIe3 PHY SRAM firmware patch..."
    cp -f ./backport/105-phy-rockchip-snps-pcie3-sram-firmware.patch target/linux/rockchip/patches-6.12/
else
    echo "ERROR: PCIe3 PHY firmware patch not found."
    exit 1
fi

#Vermagic
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/rockchip/armv8/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

# 默认管理 IP：192.168.20.1（BPI-R4 为 192.168.10.1，见其 02_target_only）
sed -i 's/192\.168\.1\.1/192.168.20.1/g' package/base-files/files/bin/config_generate

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

#exit 0
