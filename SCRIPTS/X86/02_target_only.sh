#!/bin/bash
# X86 (x86/64 generic) 设备层脚本
# 由 workflow 从 SCRIPTS/X86/ 拷入 SCRIPTS/ 后执行（与 H68K / BPI-R4 同机制）

# libsodium：x86 无 mips16 概念，保留 no-lto 会额外拖慢，按上游做法去掉
sed -i 's,no-mips16 no-lto,no-mips16,g' feeds/packages/libs/libsodium/Makefile 2>/dev/null || true

# 首次启动：裸机/虚拟机的 DMI 型号常为占位串，统一显示；并修正 intel_pstate 为 active + powersave
echo '#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

if [ ! -s /tmp/sysinfo/model ] || grep -qiE "Default string|To be filled|System manufacturer|Type2" /tmp/sysinfo/model 2>/dev/null; then
    echo "Standard PC" > /tmp/sysinfo/model
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
# Vermagic 同步（官方 profiles.json 的 .linux_kernel.vermagic）：强制平台 vermagic 与官方一致。
# 注意：latest_version 可能是不完整发布（targets 未编完 → profiles.json 404 → .vermagic 空 →
# LINUX_VERMAGIC=unknown → 内核模块 apk 依赖 kernel=~unknown 打包失败）。因此逐版本回退。
vmver=""
for _v in "${latest_version}" 25.12.5 25.12.4 25.12.3 25.12.2 25.12.1; do
    [ -n "$_v" ] || continue
    if wget -q -O profiles.json "https://downloads.openwrt.org/releases/${_v}/targets/x86/64/profiles.json" 2>/dev/null; then
        vmver="$_v"; echo "vermagic: using OpenWrt ${_v}"; break
    fi
done
[ -n "$vmver" ] || { echo "ERROR: cannot obtain profiles.json (vermagic) for any release"; exit 1; }
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
[ -s .vermagic ] || { echo "ERROR: .vermagic empty from ${vmver}"; exit 1; }
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 预配置一些插件
cp -rf ../PATCH/files ./files

find ./ -name "*.orig" | xargs rm -f 2>/dev/null || true
find ./ -name "*.rej" | xargs rm -f 2>/dev/null || true

exit 0
