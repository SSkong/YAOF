<p align="center">
<img width="768" src="https://raw.githubusercontent.com/QiuSimons/Others/master/YAOF.png" >
</p>
<p align="center">
<img alt="H68K Build" src="https://img.shields.io/github/actions/workflow/status/SSkong/YAOF/H68K-OpenWrt.yml?branch=25.12&style=for-the-badge">
<img alt="BPI-R4 Build" src="https://img.shields.io/github/actions/workflow/status/SSkong/YAOF/BPI-R4-OpenWrt.yml?branch=25.12&style=for-the-badge">
<img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/SSkong/YAOF/total?style=for-the-badge">
<img alt="GitHub License" src="https://img.shields.io/github/license/SSkong/YAOF?style=for-the-badge">
</p>

<h1 align="center">H68K / BPI-R4 OpenWrt 固件编译仓库</h1>

<p align="center">基于 <a href="https://github.com/QiuSimons/YAOF">QiuSimons/YAOF</a>（25.12 分支）fork，支持 <b>Hinlink H68K</b> 与 <b>Banana Pi BPI-R4</b>，其余设备已裁剪。</p>

<h1 align="center">请勿用于商业用途!!!</h1>

### 设备支持

- **Hinlink H68K**（RK3568，2× 千兆 + 2× 2.5G 网口），2022 旧版硬件实机验证通过
- 通过 backport [OpenWrt PR #21270](https://github.com/openwrt/openwrt/pull/21270) 适配 25.12 / kernel 6.12
- **网口布局（默认）**：WAN = **eth3（2.5GbE）**，LAN（br-lan）= eth0 / eth1 / eth2（2× 千兆 + 1× 2.5GbE）；WAN 蓝灯跟随 eth3
- **eth2/eth3（RTL8125B）2.5G 已修复并实机验证**，三层修复缺一不可：
  - PCIe3 供电挂到 GPIO2_D2 的 `vcc3v3_pcie_legacy`（2022 旧版真实供电轨）并加 `regulator-boot-on` 早期上电（原配置错挂 GPIO0_C4 时钟缓冲供电且无 boot-on）
  - 移植 RK3568 PCIe3 PHY SRAM 固件上传补丁（unifreq，firmware `fw-d54d0eb`），解决 PHY SRAM 自动加载永不完成（`p3phy lock failed` → probe -110）
  - U-Boot 侧同步供电时序，避免引导阶段电源状态不确定

- **Banana Pi BPI-R4**（MediaTek MT7988A，4× A73 / 4GB RAM，2× 10G SFP+ + 4× GbE）
- OpenWrt 25.12 官方树自带完整支持（`bananapi_bpi-r4`，同 kernel 6.12.94，无需任何 backport）
- 同时覆盖 **eMMC 与 SPI-NAND** 两种启动介质：产出 `emmc-preloader/fip/gpt` 与 `snand-preloader/fip` 全套引导件 + `squashfs-sysupgrade.itb` + `sdcard.img.gz`（SD 卡整体启动镜像）
- Wi-Fi：默认不含（本板无无线子卡）；M.2 E-key 槽日后插卡可 `opkg install kmod-mt7915e kmod-mt7915-firmware wpad-openssl` 补装
- 第一块网口布局沿用 filogic 官方默认 board.d
- **BPI-R4 专属应用**：Fan Control（官方金属壳风扇 PWM 调速）、SFPmon（SFP+ 光口 SFF-8472 数字诊断：温度/电压/光功率）、MTK-WED（MediaTek PPE/WED 硬件卸载状态页与开关）

### 固件特性（两设备通用）

- 基于原生 OpenWrt 25.12，默认管理 IP 按设备区分：**H68K = 192.168.20.1**，**BPI-R4 = 192.168.10.1**（双设备同网段并存不冲突）
- 内置升级功能可用，物理 Reset 按键可用，可无脑 opkg kmod
- 内核：BBRv3、LRNG（含 jitter 熵源）、Broadcom Fullcone-NAT、fullcone6、NAT6、NETKIT、BTF（vmlinux-btf，供 DAE 使用）（Shortcut-FE 已随上游 2026-10-16 弃用移除）
- O2 编译优化，TEO CPU 空闲调度器，mitigations=off
- 内核 zram 优化：`vm.swappiness=100` + `vm.page-cluster=0`（配合 zram-swap）
- **首次启动自动利用 eMMC 剩余空间（H68K 与 BPI-R4 均生效）**：自动将根盘最后的未分配空间建 ext4 分区（≥1GiB 才动手）并挂载到 **/opt**。H68K 走 root=PARTUUID 定位；BPI-R4 走 FIT 布局的 `PARTLABEL=production` 定位（production 分区之后即全部未分配尾部）。幂等防御：已有 LABEL=data 分区或 /opt 已挂载则跳过（ImmortalWrt 官方固件转来自带 primary 分区挂 /opt 的情况不会重复操作）。`logread | grep h68k-data` 可查看结果

### 预置插件

| 类别 | 插件 |
|---|---|
| 代理 | SSR-Plus、PassWall、OpenClash、Dae、Nikki、HomeProxy、Mihomo |
| DNS | SmartDNS（pymumu 版核心 + **WebUI** + LuCI）、mosdns |
| 广告/过滤 | AdGuardHome（nftables 重定向版）、OpenAppFilter（destan19 官方版） |
| 组网 | ZeroTier（rabbitrogi LuCI）、EasyTier、WireGuard |
| 容器 | **Docker**（sbwml fork 适配 25.12：docker/dockerd/containerd/runc）+ Dockerman |
| 新增工具 | Fluxora（WAN 流量监控）、Online Upgrade（在线升级）、SubStore（订阅管理）、Ghacc（GitHub 加速）、OxiDNS、看门狗（登录防护） |
| QoS | SQM（官方 luci-app-sqm + sqm-scripts，cake/fq_codel；曾用 QoSmate 因其 hotplug 在多网口设备自激励循环已移除） |
| 存储/文件 | HarborFile Pro（文件管理，ucode 后端）、OpenList2（OpenList/AList 网盘挂载，sbwml）、DiskMan（磁盘管理，lisaac） |
| 其他 | DDNS、网易云解锁、UPnP、网络唤醒、USB 打印、Zram Swap、WolMon（唤醒+在线监控）、Natmap、Bandix、Einat |

- 完整功能由 SEED 定义（公共体 `SEED/common.seed` + 设备层 `SEED/<设备>/device.seed`，构建时拼装），可自行裁剪
- ss 协议在 armv8 上实现了 aes 硬件加速（请<b>仅使用 aead 加密</b>的连接方式）
- 有任何问题请先 ssh 进入后台输入 `fuck` 回车，等待重启后确认问题是否解决

### 使用

1. **触发编译**：GitHub Actions → `H68K-OpenWrt` / `BPI-R4-OpenWrt` → Run workflow（`build_firmware=true`）；也可用 `OpenWrt-Matrix` 选择设备
2. **BPI-R4 产物**：`-sfs.zip`（sysupgrade.itb）、`-ext4.zip`（sdcard.img.gz，SD 卡烧录），`-factory.zip`（预加载/引导整包，eMMC/NAND 从零刷写）；H68K 产物为 `-ext4.zip` / `-sfs.zip`（sysupgrade.img）
3. **下载固件**：[Releases](https://github.com/SSkong/YAOF/releases)（编译成功自动发布）
4. **刷机**：H68K 走 rockchip 常规方式（RK 开发工具 / dd / SD 卡）；BPI-R4 最简流程 = `sdcard.img.gz` dd 到 TF 卡直接启动，后续从 LuCI 用 sysupgrade.itb 升级
5. 登录：H68K `192.168.20.1` / BPI-R4 `192.168.10.1`，root（初始无密码，OpenWrt 默认）

### 源码结构（相对上游的定制）

- 分支 25.12 = 上游最新提交 + 单个定制化 squash 提交（`README` 文档保持上游同步）
- 构建分 **minimal / full** 两档（workflow `profile` 入参：`auto` 无缓存自动编最小、有缓存编完整；或强制 `minimal`/`full`）；发布也分档：full → 正式 Release `OpenWRT-<ver>`，minimal → 预发布 `OpenWRT-<ver>-minimal`，不再混存：
  - `SEED/common.mini.seed` + `SEED/<设备>/device.mini.seed`：最小固件（核心+LuCI+网络+加密+网卡驱动+/opt 自动分区，**不含代理/重依赖**），冷启动 6h 内可完成
  - `SEED/common.seed` + `SEED/<设备>/device.seed`：完整固件（全部插件），依赖先前 minimal 建立的工具链+golang 缓存增量编译；构建时按 `cat common + device` 装配为 .config
  - 设备层只放两设备差异行（目标/设备选择、RNGD 方案、BPI-R4 三专属应用、禁用 recovery initramfs）；公共体改一处双设备同步生效
  - 缓存已覆盖工具链（cachewrtbuild）+ Go 编译/模块缓存（真实路径 `openwrt/tmp/go-build` 与 `openwrt/dl/go-mod-cache`，由 golang-package.mk 决定）
- `SCRIPTS/01_get_ready.sh`：源码树准备（OpenWrt release + 25.12 分支混合 packages；已裁掉 immortalwrt/lede 等无用克隆）
- `SCRIPTS/02_prepare_package.sh`：包定制核心（上述全部插件的替换/新增/依赖修复均在此）
- `SCRIPTS/H68K/02_target_only.sh`：H68K backport 应用、vermagic 同步、内核配置注入
- `SCRIPTS/BPI-R4/02_target_only.sh`：BPI-R4 无需 backport（官方树自带），仅 vermagic 同步 + files 注入
- `SCRIPTS/H68K/backport/h68k-backport.patch`：PR #21270 + PCIe 供电修复（GPIO2_D2 rail + regulator-boot-on + 网口布局 WAN=eth3）
- `SCRIPTS/H68K/backport/105-phy-rockchip-snps-pcie3-sram-firmware.patch`：RK3568 PCIe3 PHY SRAM 固件上传补丁（fw-d54d0eb）
- `PATCH/files/etc/uci-defaults/99-h68k-data-partition.sh`：首启自动分区脚本（eMMC 尾部 ≥1GiB → ext4 → 挂载 /opt）
- 上游同步：fetch QiuSimons/YAOF 25.12 → squash merge 重建定制提交（上游改动若与我们不触碰的文件冲突，取上游）

### 注意事项

- **端口布局 WAN=eth3 仅在首次启动/恢复出厂时生效**：sysupgrade 保留配置会沿用旧映射，请刷机不保留配置或手动在 LuCI 调整
- 请勿用于商业用途
- 电源质量影响稳定性（RK3568 多网口设备，建议使用优质电源）
- 本次裁剪仅保留 H68K 与 BPI-R4，需要其他设备请使用上游 [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)

### 鸣谢

|               [ImmortalWrt](https://github.com/immortalwrt)               |              [coolsnowwolf](https://github.com/coolsnowwolf)              |                    [Lienol](https://github.com/Lienol)                    |
| :-----------------------------------------------------------------------: | :-----------------------------------------------------------------------: | :-----------------------------------------------------------------------: |
| <img width="60" src="https://avatars.githubusercontent.com/u/53193414"/>  | <img width="60" src="https://avatars.githubusercontent.com/u/31687149" /> | <img width="60" src="https://avatars.githubusercontent.com/u/23146169" /> |
|            [NoTengoBattery](https://github.com/NoTengoBattery)            |                    [tty228](https://github.com/tty228)                    |                  [destan19](https://github.com/destan19)                  |
| <img width="60" src="https://avatars.githubusercontent.com/u/11285513" /> | <img width="60" src="https://avatars.githubusercontent.com/u/33397881" /> | <img width="60" src="https://avatars.githubusercontent.com/u/3950091" />  |
|                 [jerrykuku](https://github.com/jerrykuku)                 |                    [lisaac](https://github.com/lisaac)                    |             [rufengsuixing](https://github.com/rufengsuixing)             |
| <img width="60" src="https://avatars.githubusercontent.com/u/9485680" />  | <img width="60" src="https://avatars.githubusercontent.com/u/3320969" />  | <img width="60" src="https://avatars.githubusercontent.com/u/22387141" /> |
|                     [ElonH](https://github.com/ElonH)                     |                   [NateLol](https://github.com/NateLol)                   |                   [kiddin9](https://github.com/kiddin9)                   |
| <img width="60" src="https://avatars.githubusercontent.com/u/32666230" /> | <img width="60" src="https://avatars.githubusercontent.com/u/5166306" />  | <img width="60" src="https://avatars.githubusercontent.com/u/48883331" /> |
|              [AmadeusGhost](https://github.com/AmadeusGhost)              |                [1715173329](https://github.com/1715173329)                |                 [vernesong](https://github.com/vernesong)                 |
| <img width="60" src="https://avatars.githubusercontent.com/u/42570690" /> | <img width="60" src="https://avatars.githubusercontent.com/u/22235437" /> | <img width="60" src="https://avatars.githubusercontent.com/u/42875168" /> |

<p align="center"><b>OpenWrt 25.12 · H68K + BPI-R4</b></p>