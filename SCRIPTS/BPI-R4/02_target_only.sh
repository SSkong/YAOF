#!/bin/bash
clear

# BPI-R4 (MediaTek MT7988A): OpenWrt 25.12 官方树自带完整支持（bananapi_bpi-r4，
# 覆盖 eMMC 与 SPI-NAND 两种启动介质），无需任何 backport / PHY 补丁（对比 H68K：
# rockchip 侧需要 PR#21270 backport + RK3568 PCIe3 PHY SRAM 固件补丁）。
# filogic 内核同为 6.12.94，02_prepare_package.sh 的全部 generic 内核补丁
# （BBRv3/LRNG/bcmfullcone/BTF 等）直接适用。
# 默认 2.5G SFP+ 光口eth *1? 具体口位: 2x 10G PHY-less SFP+ 与 4x GbE (MT7530)，
# 详见 OpenWrt wiki。WAN/LAN 布局沿用 filogic 默认 board.d。

#Vermagic（与 H68K 相同机制，profiles.json 路径换 filogic）
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/mediatek/filogic/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件（zram sysctl、NIC buffer 最大化等 hotplug；首启自动分区脚本对
# BPI-R4 的 eMMC/sdcard root 同样适用——rootfs 分区后的未分配尾部扩 /opt）
cp -rf ../PATCH/files ./files

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

#exit 0
