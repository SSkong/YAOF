<p align="center">
<img width="768" src="https://raw.githubusercontent.com/QiuSimons/Others/master/YAOF.png" >
</p>
<p align="center">
<img alt="H68K Build" src="https://img.shields.io/github/actions/workflow/status/SSkong/YAOF/H68K-OpenWrt.yml?branch=25.12&style=for-the-badge">
<img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/SSkong/YAOF/total?style=for-the-badge">
<img alt="GitHub License" src="https://img.shields.io/github/license/SSkong/YAOF?style=for-the-badge">
</p>

<h1 align="center">H68K 专用 OpenWrt 固件编译仓库</h1>

<p align="center">基于 <a href="https://github.com/QiuSimons/YAOF">QiuSimons/YAOF</a>（25.12 分支）fork，专精 <b>Hinlink H68K</b> 编译，其余设备已裁剪。</p>

<h1 align="center">请勿用于商业用途!!!</h1>

### 设备支持

- **Hinlink H68K**（RK3568，2× 千兆 + 2× 2.5G 网口），2022 旧版硬件实机验证通过
- 通过 backport [OpenWrt PR #21270](https://github.com/openwrt/openwrt/pull/21270) 适配 25.12 / kernel 6.12
- **网口布局（默认）**：WAN = **eth3（2.5GbE）**，LAN（br-lan）= eth0 / eth1 / eth2（2× 千兆 + 1× 2.5GbE）；WAN 蓝灯跟随 eth3
- **eth2/eth3（RTL8125B）2.5G 已修复并实机验证**，三层修复缺一不可：
  - PCIe3 供电挂到 GPIO2_D2 的 `vcc3v3_pcie_legacy`（2022 旧版真实供电轨）并加 `regulator-boot-on` 早期上电（原配置错挂 GPIO0_C4 时钟缓冲供电且无 boot-on）
  - 移植 RK3568 PCIe3 PHY SRAM 固件上传补丁（unifreq，firmware `fw-d54d0eb`），解决 PHY SRAM 自动加载永不完成（`p3phy lock failed` → probe -110）
  - U-Boot 侧同步供电时序，避免引导阶段电源状态不确定

### 固件特性

- 基于原生 OpenWrt 25.12，默认管理 IP **192.168.20.1**
- 内置升级功能可用，物理 Reset 按键可用，可无脑 opkg kmod
- 内核：BBRv3、LRNG（含 jitter 熵源）、Broadcom Fullcone-NAT、fullcone6、NAT6、NETKIT、BTF（vmlinux-btf，供 DAE 使用）（Shortcut-FE 已随上游 2026-10-16 弃用移除）
- O2 编译优化，TEO CPU 空闲调度器，mitigations=off
- 内核 zram 优化：`vm.swappiness=100` + `vm.page-cluster=0`（配合 zram-swap）
- **首次启动自动利用 eMMC 剩余空间**：自动将根盘最后的未分配空间建 ext4 分区（≥1GiB 才动手）并挂载到 **/opt**（适合 Docker 数据目录、OpenList2 网盘缓存、Entware 等大文件场景；`logread | grep h68k-data` 可查看结果）

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
| 其他 | DDNS、网易云解锁、UPnP、迅雷快鸟、网络唤醒、USB 打印、Zram Swap、WolPlus、Natmap、Bandix、Einat |

- 完整功能由 SEED/H68K/config.seed 定义，可自行裁剪
- ss 协议在 armv8 上实现了 aes 硬件加速（请<b>仅使用 aead 加密</b>的连接方式）
- 有任何问题请先 ssh 进入后台输入 `fuck` 回车，等待重启后确认问题是否解决

### 使用

1. **触发编译**：GitHub Actions → `H68K-OpenWrt` → Run workflow（`build_firmware=true`）
2. **下载固件**：[Releases](https://github.com/SSkong/YAOF/releases)（ext4 / squashfs 两版，编译成功自动发布）
3. **刷机**：rockchip 常规方式（RK 开发工具 / dd 写入 eMMC / SD 卡）
4. 登录：`192.168.20.1`，root（初始无密码，OpenWrt 默认）

### 源码结构（相对上游的定制）

- 分支 25.12 = 上游最新提交 + 单个定制化 squash 提交（`README` 文档保持上游同步）
- `SCRIPTS/01_get_ready.sh`：源码树准备（OpenWrt release + 25.12 分支混合 packages；已裁掉 immortalwrt/lede 等无用克隆）
- `SCRIPTS/02_prepare_package.sh`：包定制核心（上述全部插件的替换/新增/依赖修复均在此）
- `SCRIPTS/H68K/02_target_only.sh`：H68K backport 应用、vermagic 同步、内核配置注入
- `SCRIPTS/H68K/backport/h68k-backport.patch`：PR #21270 + PCIe 供电修复（GPIO2_D2 rail + regulator-boot-on + 网口布局 WAN=eth3）
- `SCRIPTS/H68K/backport/105-phy-rockchip-snps-pcie3-sram-firmware.patch`：RK3568 PCIe3 PHY SRAM 固件上传补丁（fw-d54d0eb）
- `PATCH/files/etc/uci-defaults/99-h68k-data-partition.sh`：首启自动分区脚本（eMMC 尾部 ≥1GiB → ext4 → 挂载 /opt）
- 上游同步：fetch QiuSimons/YAOF 25.12 → squash merge 重建定制提交（上游改动若与我们不触碰的文件冲突，取上游）

### 注意事项

- **端口布局 WAN=eth3 仅在首次启动/恢复出厂时生效**：sysupgrade 保留配置会沿用旧映射，请刷机不保留配置或手动在 LuCI 调整
- 请勿用于商业用途
- 电源质量影响稳定性（RK3568 多网口设备，建议使用优质电源）
- 本次裁剪仅保留 H68K，需要其他设备请使用上游 [QiuSimons/YAOF](https://github.com/QiuSimons/YAOF)

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

<p align="center"><b>OpenWrt 25.12 · H68K only</b></p>