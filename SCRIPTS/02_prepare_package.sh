#!/bin/bash
clear

### 基础部分 ###
# 使用 O2 级别的优化
sed -i 's/Os/O2/g' include/target.mk
# 更新 Feeds
./scripts/feeds update -a
./scripts/feeds install -a

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
# LRNG（设备可关：BPI-R4/MT7988A 实测 LRNG 开机挂死——由 workflow 矩阵 enable_lrng 字段注入 ENABLE_LRNG 环境变量控制，BPI-R4=0 跳过）
if [ "${ENABLE_LRNG:-1}" = "1" ]; then
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
fi
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
# set nf_conntrack_expect_max for fullcone
wget -qO - https://github.com/openwrt/openwrt/commit/bbf39d07.patch | patch -p1
# FW4
mkdir -p package/network/config/firewall4/patches
# fullcone 实现已随上游切换为独立包 flowcone（eBPF/TCX，见 SEED 的 luci-app-flowcone）：
# BCM 内核补丁（bcmfullcone hack）、firewall4 999-01、LuCI 0001 三件套全部停用并已从仓库删除；
# 此处仅保留 nf_conntrack_expect_max 调优与自定义 nft 命令补丁（与 fullcone 无关，仍在用）。
# NAT6 亦随上游 3710daa 移除（seed 项与 0003 LuCI 补丁一并停用）。
# custom nft command
patch -p1 < ../PATCH/pkgs/firewall/100-openwrt-firewall4-add-custom-nft-command-support.patch
cp -f ../PATCH/pkgs/firewall/firewall4_patches/*.patch ./package/network/config/firewall4/patches/
# Patch LuCI 以支持自定义 nft 规则
pushd feeds/luci
patch -p1 <../../../PATCH/pkgs/firewall/luci/0004-luci-add-firewall-add-custom-nft-rule-support.patch
popd

### Other Kernel Hack 部分 ###
# make olddefconfig
wget -qO - https://github.com/openwrt/openwrt/commit/c21a3570.patch | patch -p1
# igc-fix
# igc-fix（x86 专用，H68K-only 仓库不构建 x86，已移除：原从 lede 树取 996-intel-igc-i225-i226-disable-eee）
# btf
cp -rf ../PATCH/kernel/btf/* ./target/linux/generic/hack-${KERNEL_VERSION}/

### 获取额外的基础软件包 ###
# Disable Mitigations
sed -i 's,rootwait,rootwait mitigations=off,g' target/linux/rockchip/image/default.bootscript
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-efi.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-iso.cfg
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-pc.cfg

### ADD PKG 部分 ###
# OpenWrt-Add 上游已重组为 apps/ core/ legacy/ themes/ invasive/ 五组；
# 仍按“扁平”方式投放（各组内包目录直接落到 package/new/），保持本仓库既有路径引用不变
mkdir -p ./package/new
for _grp in apps legacy themes invasive; do
    if [ -d "../OpenWrt-Add/${_grp}" ]; then
        cp -rf "../OpenWrt-Add/${_grp}/." ./package/new/ 2>/dev/null || true
    fi
done
# sing-box naive outbound：OpenWrt-Add 的 imm_pkg 已自带 libcronet 包（配 gn/host 基建，
# 由上游 b8c59d3+5a52e68 引入），naive 协议原生支持，无需再打禁用钉子（历史版本 imm_pkg
# 缺 libcronet 曾致链接失败，当时以 sed 禁 naive 绕过，现已不需要）。

### DAE / HONK (189160 fork 替换 OpenWrt-Add 版) ###
# OpenWrt-Add 自带 dae/honk 全套（luci-app-dae 内含源码编译 dae、luci-app-daed、luci-app-honk 内含 honk），删除防同名顶替
rm -rf ./package/new/luci-app-dae ./package/new/luci-app-daed ./package/new/luci-app-honk
# dae: 189160 fork 的 dae 核心为 prebuilt 注入式（Makefile 硬性要求 files/prebuilt/aarch64/dae，
# 其自家 CI 由 daeuniverse release 下载注入）。此处等价注入：版本与 sha256 动态读自其
# Makefile 钉子（DAE_RELEASE / DAE_HASH_AARCH64），仓库更新时无需改此段。
git clone --depth 1 https://github.com/189160/luci-app-dae.git /tmp/dae189-src
DAE_REL="$(grep '^DAE_RELEASE:=' /tmp/dae189-src/dae/Makefile | cut -d= -f2)"
DAE_HASH="$(grep '^DAE_HASH_AARCH64:=' /tmp/dae189-src/dae/Makefile | cut -d= -f2)"
curl -fsSL --retry 3 -o /tmp/dae-prebuilt.tar.xz "https://github.com/daeuniverse/dae/releases/download/${DAE_REL}/dae-linux-arm64.tar.xz"
[ "$(sha256sum /tmp/dae-prebuilt.tar.xz | cut -d' ' -f1)" = "$DAE_HASH" ] || { echo "ERROR: dae prebuilt sha256 mismatch (${DAE_REL})"; exit 1; }
mkdir -p /tmp/dae189-rel && tar -xJf /tmp/dae-prebuilt.tar.xz -C /tmp/dae189-rel
mkdir -p /tmp/dae189-src/dae/files/prebuilt/aarch64
install -m 755 /tmp/dae189-rel/usr/bin/dae /tmp/dae189-src/dae/files/prebuilt/aarch64/dae
cp -rf /tmp/dae189-src/dae ./package/new/dae
# dae Makefile 修正（target arch 差异，2025 实测）：其 DAE_PREBUILT 选择仅识别 x86_64 与
# aarch64_generic，而 BPI-R4(mediatek/filogic) 的 ARCH_PACKAGES=aarch64_cortex-a53 落入 else 空
# 分支 → install 时 test -f "" 失败(秒败)。改为任意 aarch64 前缀即命中(arm64 静态二进同用)。
sed -i 's/else ifeq (\$(ARCH_PACKAGES),aarch64_generic)/else ifneq (\$(findstring aarch64,\$(ARCH_PACKAGES)),)/' ./package/new/dae/Makefile
cp -rf /tmp/dae189-src/luci-app-dae ./package/new/luci-app-dae
rm -rf /tmp/dae189-src /tmp/dae189-rel /tmp/dae-prebuilt.tar.xz
# honk: 189160 fork 的 honk 核心为标准 PKG_SOURCE 下载（fork release 资产 + PKG_HASH 校验），自包含无需注入
git clone --depth 1 https://github.com/189160/luci-app-honk.git /tmp/honk189-src
cp -rf /tmp/honk189-src/honk ./package/new/honk
cp -rf /tmp/honk189-src/luci-app-honk ./package/new/luci-app-honk
rm -rf /tmp/honk189-src

### FCHOMO (fcshark-org: mihomo 核心替换为 metacubex 官方源版 + FullCombo LuCI) ###
# 冲突处理：OpenWrt-Add 的 OpenWrt-mihomo/{mihomo-meta,mihomo-alpha} 与本 mihomo 均
# PROVIDES:=mihomo 且 ALTERNATIVES 到 /usr/bin/mihomo（100 vs 300），同装必冲突。
# 删 meta/alpha 核心，保留 nikki 与 luci-app-nikki（nikki 仅依赖虚包 mihomo，
# 由 fchomo 的 mihomo 满足；核心共用一个 /usr/libexec/mihomo-core 二进制）。
rm -rf ./package/new/OpenWrt-mihomo/mihomo-meta ./package/new/OpenWrt-mihomo/mihomo-alpha
rm -rf ./package/new/openwrt_helloworld/mihomo-meta ./package/new/openwrt_helloworld/mihomo-alpha
rm -rf ./package/feeds/packages/mihomo 2>/dev/null || true
git clone --depth 1 https://github.com/fcshark-org/openwrt-fchomo.git /tmp/fchomo-src
cp -rf /tmp/fchomo-src/mihomo ./package/new/mihomo
cp -rf /tmp/fchomo-src/luci-app-fchomo ./package/new/luci-app-fchomo
rm -rf /tmp/fchomo-src
# SFE 已随上游 d36dda0 弃用；仍删 OpenWrt-Add 自带 shortcut-fe（防包残留顶替）
rm -rf ./package/new/shortcut-fe
# kmod-nft-fullcone 不启用：fullcone 现在由 flowcone（eBPF/TCX 独立包）实现，
# 同时从 addition-trans-zh 的 DEPENDS 里摘掉该 kmod（包已不存在）。
rm -rf ./package/new/lede_pkg/fullconenat-nft
sed -i 's/ +kmod-nft-fullcone//' ./package/new/addition-trans-zh/Makefile
# OpenWrt-Add 自带旧版 luci-app-adguardhome (rufengsuixing 1.8.20221120，Lua 版，
# 与 w9315273 版同名冲突且依赖已删除的 feeds adguardhome 核心包)，必须删除
rm -rf ./package/new/openwrt_pkgs/luci-app-adguardhome
# OpenAppFilter：OpenWrt-Add 为旧 fork 快照，替换为 destan19 原作者版（应用特征库更新）
rm -rf ./package/new/OpenAppFilter
git clone --depth 1 https://github.com/destan19/OpenAppFilter.git ./package/new/OpenAppFilter
# zerotier 核心包保留 feeds 官方版（rabbitrogi LuCI 依赖它），仅从删除列表移除
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,frp,microsocks,shadowsocks-libev,daed,adguardhome}
rm -rf package/feeds/packages/adguardhome
rm -rf feeds/luci/applications/{luci-app-frps,luci-app-frpc,luci-app-zerotier,luci-app-adguardhome,luci-app-smartdns}
rm -rf package/feeds/luci/luci-app-adguardhome
# zerotier LuCI 双清（feeds 源码删了还要删符号链接，防止旧版顶替 rabbitrogi 版）
rm -rf package/feeds/luci/luci-app-zerotier
# smartdns 核心替换为 pymumu 版，LuCI 也替换为 pymumu 版（与核心版本匹配）
rm -rf feeds/packages/net/smartdns
rm -rf package/feeds/packages/smartdns
rm -rf package/feeds/luci/luci-app-smartdns
rm -rf feeds/packages/utils/coremark
# einat 已换为 flowcone（两者同为 Rust/eBPF；flowcone 的 Makefile 直接 DEPENDS +vmlinux-btf，
# 无需 einat 那样的 @KERNEL_DEBUG_INFO_BTF 改写。若将来重新启用 einat，需恢复上一行 sed）
git clone --depth 1 https://github.com/QiuSimons/vmlinux-btf ./package/new/vmlinux-btf

### AdGuardHome (w9315273 版，nftables 重定向) ###
git clone --depth 1 https://github.com/w9315273/luci-app-adguardhome.git ./package/new/luci-app-adguardhome
# 核心下载/解压脚本需要 xz，上游 Makefile 未声明依赖，补上 xz-utils
sed -i 's/DEPENDS:=+luci-base +rpcd-mod-ucode +uclient-fetch +tar/DEPENDS:=+luci-base +rpcd-mod-ucode +uclient-fetch +tar +xz-utils/' ./package/new/luci-app-adguardhome/Makefile

### EasyTier ###
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git /tmp/easytier-src
cp -rf /tmp/easytier-src/easytier ./package/new/easytier
cp -rf /tmp/easytier-src/luci-app-easytier ./package/new/luci-app-easytier
cp -f /tmp/easytier-src/version.mk ./package/new/easytier/version.mk 2>/dev/null || true
cp -f /tmp/easytier-src/version.mk ./package/new/luci-app-easytier/version.mk 2>/dev/null || true
rm -rf /tmp/easytier-src

### SQM (官方 feeds：luci-app-sqm + sqm-scripts；替代 QoSmate——其 hotplug 在多网口设备上有自激励循环缺陷) ###

### HarborFile Pro (whzhni1: 文件管理 Web 前端, ucode 后端) ###
git clone --depth 1 https://github.com/whzhni1/luci-app-harbor-file-pro.git /tmp/harbor-src
cp -rf /tmp/harbor-src/luci-app-harbor-file-pro ./package/new/luci-app-harbor-file-pro
rm -rf /tmp/harbor-src

### OpenList2 (sbwml: Go 核心 + LuCI 前端, 网盘挂载; 标准 golang feeds 机制) ###
git clone --depth 1 https://github.com/sbwml/luci-app-openlist2.git /tmp/openlist2-src
cp -rf /tmp/openlist2-src/openlist2 ./package/new/openlist2
cp -rf /tmp/openlist2-src/luci-app-openlist2 ./package/new/luci-app-openlist2
rm -rf /tmp/openlist2-src

### DiskMan (lisaac: 磁盘管理; Parted.Makefile 不带, feeds 自带 parted) ###
git clone --depth 1 https://github.com/lisaac/luci-app-diskman.git /tmp/diskman-src
cp -rf /tmp/diskman-src/applications/luci-app-diskman ./package/new/luci-app-diskman
rm -rf /tmp/diskman-src

### Watchdog (sirpdboy 安全看门狗：WEB/SSH 登录监控自动拉黑) ###
git clone --depth 1 https://github.com/sirpdboy/luci-app-watchdog.git /tmp/watchdog-src
cp -rf /tmp/watchdog-src/luci-app-watchdog ./package/new/luci-app-watchdog
cp -rf /tmp/watchdog-src/watchdog ./package/new/watchdog
rm -rf /tmp/watchdog-src

### ZeroTier (rabbitrogi 版 LuCI 前端，核心用 feeds 官方 zerotier) ###
# OpenWrt-Add 自带 luci-app-zerotier，删除防同名顶替
rm -rf ./package/new/luci-app-zerotier
git clone --depth 1 https://github.com/rabbitrogi/luci-app-zerotier.git ./package/new/luci-app-zerotier

### SmartDNS (pymumu 版核心 + LuCI 前端) ###
git clone --depth 1 https://github.com/pymumu/openwrt-smartdns.git ./package/new/smartdns
# 上游 PKG_MIRROR_HASH 与本构建系统 git archive+zstd 打包产物哈希不一致
# （上游哈希为其 CI 环境产物 d8ca4173...，本 runner 确定性生成 60787d63...），
# 源码已固定 commit（PKG_SOURCE_VERSION），改 skip 跳过镜像哈希校验（同 mihomo-meta/dae 做法）
sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/' ./package/new/smartdns/Makefile
# smartdns-webui 子源（Download/smartdns-webui 无条件注册，make download 必然拉取）的
# MIRROR_HASH 同样是上游 CI 环境产物，与 runner 生成哈希不一致导致 download 阶段报 ERROR；
# smartdns-ui 包 SEED 未选中，编译期不消费该文件，此处一并 skip 消除噪音并为将来启用留路
sed -i '/^define Download\/smartdns-webui/,/^endef/ s/MIRROR_HASH:=.*/MIRROR_HASH:=skip/' ./package/new/smartdns/Makefile
git clone --depth 1 https://github.com/pymumu/luci-app-smartdns.git ./package/new/luci-app-smartdns

### 新增应用包 ###
# Fluxora (WAN 流量监控，PKG_NAME=luci-app-wan-traffic)
git clone --depth 1 https://github.com/cndoin/luci-app-fluxora.git ./package/new/luci-app-fluxora
# Online Upgrade (在线升级)
git clone --depth 1 https://github.com/Arthur97172/luci-app-online-upgrade.git ./package/new/luci-app-online-upgrade
# SubStore (订阅管理)
git clone --depth 1 https://github.com/Arthur97172/luci-app-substore.git ./package/new/luci-app-substore
# Ghacc (GitHub 加速，PKG_NAME=ghacc)
git clone --depth 1 https://github.com/sqchr888/luci-app-ghacc.git ./package/new/luci-app-ghacc
# OxiDNS (DNS 工具)
git clone --depth 1 https://github.com/svenshi/luci-app-oxidns.git ./package/new/luci-app-oxidns
# 网络唤醒监控（my1639963/luci-app-wolmon 替换 wolplus：唤醒 + 在线状态监控一体，
# ARP/ping 轮询 + 唤醒后 IP 自动发现）。原 OpenWrt-Add 的 wolplus/services-wolplus 均删。
rm -rf ./package/new/luci-app-services-wolplus ./package/new/openwrt_pkgs/luci-app-services-wolplus
rm -rf ./package/new/luci-app-wolplus
git clone --depth 1 https://github.com/my1639963/luci-app-wolmon.git /tmp/wolmon-src
cp -rf /tmp/wolmon-src/src/luci-app-wolmon ./package/new/luci-app-wolmon
rm -rf /tmp/wolmon-src
# wolmon Makefile 用相对路径 include ../../luci.mk（feeds 内布局），改 feeds 绝对路径
sed -i 's|^include ../../luci.mk$|include $(TOPDIR)/feeds/luci/luci.mk|' ./package/new/luci-app-wolmon/Makefile
# Shadcn 主题（shadcn/ui 设计语言，现代侧边栏 LuCI 主题）
git clone --depth 1 https://github.com/eamonxg/luci-theme-shadcn.git ./package/new/luci-theme-shadcn

### 获取额外的 LuCI 应用、主题和依赖 ###
# RK
sed -i '/REQUIRE_IMAGE_METADATA/d' target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh
wget https://github.com/coolsnowwolf/lede/raw/refs/heads/master/target/linux/rockchip/patches-6.12/991-arm64-dts-rockchip-add-more-cpu-operating-points-for.patch -O target/linux/rockchip/patches-6.12/991.patch
wget https://github.com/coolsnowwolf/lede/raw/refs/heads/master/target/linux/rockchip/patches-6.12/992-rockchip-rk3399-overclock-to-2.2-1.8-GHz.patch -O target/linux/rockchip/patches-6.12/992.patch
# 更换 Nodejs 版本
rm -rf ./feeds/packages/lang/node
rm -rf ./package/new/feeds_packages_lang_node-prebuilt
cp -rf ../OpenWrt-Add/apps/feeds_packages_lang_node-prebuilt ./feeds/packages/lang/node
### node-prebuilt 修复（OpenWrt-Add 移动目标的两处缺陷，2025 实测）###
#  (1) 原 PKG_VERSION 动态拉取 GitHub tags，CI 中易瞬时为空 → 一次性解析(带重试)钉入 Makefile
#  (2) $(ARCH_PACKAGES) 在本 fork 展开为 aarch64_cortex_a53(下划线)，而 sbwml asset 名为
#      aarch64_cortex-a53(连字符) → 统一替换为连字符形式（H68K/BPI-R4 均为 aarch64）
NODE_VER="$(curl -fsSL --retry 3 --max-time 30 https://api.github.com/repos/sbwml/node_workflow/tags 2>/dev/null | grep '"name"' | head -n 1 | sed -E 's/.*"name": "v([^"]+)".*/\1/' || true)"
[ -n "$NODE_VER" ] || NODE_VER="22.23.2"
echo "node-prebuilt: pinned PKG_VERSION=${NODE_VER}, asset=aarch64_cortex-a53"
sed -i -E "s|^PKG_VERSION:=.*|PKG_VERSION:=${NODE_VER}|" feeds/packages/lang/node/Makefile
sed -i 's#\$(ARCH_PACKAGES)#aarch64_cortex-a53#g' feeds/packages/lang/node/Makefile
# 更换 golang 版本
rm -rf ./feeds/packages/lang/golang
cp -rf ../openwrt_pkg_ma/lang/golang ./feeds/packages/lang/golang
#git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
# gn
rm -rf ./feeds/packages/devel/gn
cp -rf ../imm_pkg/devel/gn ./feeds/packages/devel/gn
# apk
pushd feeds/luci
wget -qO- https://github.com/sbwml/r4s_build_script/raw/refs/heads/master/openwrt/patch/luci/applications/luci-app-package-manager/0001-luci-app-package-manager-support-installing-uploaded.patch | patch -p1
popd

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
# Docker 容器：sbwml fork 适配 OpenWrt 25.12（参考 bpi-r4 方案）
# - 修复 docker/dockerd/containerd/runc 25.12 兼容性问题
# - luci-app-dockerman 使用 openwrt-25.12 分支，luci-lib-docker 用 feeds 官方版
# - 替换 feeds 源码，末尾的 feeds update -i + install -a 会刷新索引重建链接
rm -rf ./feeds/luci/applications/luci-app-dockerman
git clone -q --depth 1 -b openwrt-25.12 https://github.com/sbwml/luci-app-dockerman.git ./feeds/luci/applications/luci-app-dockerman
rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc}
git clone -q --depth 1 https://github.com/sbwml/packages_utils_docker.git feeds/packages/utils/docker
git clone -q --depth 1 https://github.com/sbwml/packages_utils_dockerd.git feeds/packages/utils/dockerd
git clone -q --depth 1 https://github.com/sbwml/packages_utils_containerd.git feeds/packages/utils/containerd
# containerd vendor 缺 urfave/cli 的 embed 文件（autocomplete、markdown.md.gotmpl）时，
# Go //go:embed 编译期报 "no matching files found"，补钩子创建占位文件。
# 必须带 [ -e ] 守卫：2.4.1 该路径缺失（造文件），2.4.2 起 urfave/cli/v3/autocomplete 变成
# 目录，`echo "" > 目录` 会报 "Is a directory" 直接挂掉整个 containerd 编译（2026-10-29 三台实测）。
sed -i '/echo "v\$(PKG_VERSION)" >.*info\/git/a\\tmkdir -p $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli/v3\n\t[ -e $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli/v3/autocomplete ] || echo "" > $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli/v3/autocomplete\n\tmkdir -p $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli-docs/v3\n\t[ -e $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli-docs/v3/markdown.md.gotmpl ] || echo "" > $(PKG_BUILD_DIR)/$(MAKE_PATH)/vendor/github.com/urfave/cli-docs/v3/markdown.md.gotmpl' feeds/packages/utils/containerd/Makefile
git clone -q --depth 1 https://github.com/sbwml/packages_utils_runc.git feeds/packages/utils/runc
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
cp -rf ../OpenWrt-Add/core/tools/clean-overlay.sh ./package/base-files/files/usr/bin/fuck
# 默认管理 IP 按设备区分（下沉到各设备 02_target_only.sh）：
#   H68K   -> 192.168.20.1
#   BPI-R4 -> 192.168.10.1
#   X86    -> 192.168.1.1（默认，不改）
# 生成默认配置及缓存
rm -rf .config
sed -i 's,CONFIG_WERROR=y,# CONFIG_WERROR is not set,g' target/linux/generic/config-${KERNEL_VERSION}

./scripts/feeds update -i
./scripts/feeds install -a

#exit 0
