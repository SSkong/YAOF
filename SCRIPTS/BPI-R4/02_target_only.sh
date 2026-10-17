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

# BPI-R4 专属包（仅 mediatek/filogic 相关，放设备层而非共用的 02_prepare_package.sh）
# 风扇控制（@TARGET_mediatek_filogic 限定，BPI-R4 官方金属壳风扇 PWM 调速）
git clone --depth 1 https://github.com/ntbowen/luci-app-fan-bpir4.git ./package/new/luci-app-fan-bpir4
# SFP/SFP+ 光口监控（SFF-8472 数字诊断：温度/电压/光功率，BPI-R4 双 10G SFP+ 用）
git clone --depth 1 https://github.com/localhost-copilot/luci-app-sfpmon.git ./package/new/luci-app-sfpmon
# MediaTek PPE/WED 硬件卸载状态页（flow table、WED、口状态、硬件加速开关；嵌套目录取内层）
git clone --depth 1 https://github.com/z21100644/luci-app-mtk-wed.git /tmp/mtkwed-src
cp -rf /tmp/mtkwed-src/luci-app-mtk-wed ./package/new/luci-app-mtk-wed
rm -rf /tmp/mtkwed-src

# 默认管理 IP：192.168.10.1（与 H68K 的 192.168.20.1 区分，双设备同网段并存不打架）
sed -i 's/192\.168\.1\.1/192.168.10.1/g' package/base-files/files/bin/config_generate

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f

#exit 0
