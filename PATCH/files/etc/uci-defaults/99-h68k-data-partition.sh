#!/bin/sh
# H68K / BPI-R4 首启自动格式化剩余空间并挂载 /opt（ext4）
# - H68K：root=PARTUUID 定位；BPI-R4：root=/dev/fit0（FIT 虚拟设备）→ PARTLABEL=production 定位
# uci-defaults 机制：首次启动执行一次，成功后脚本自删；幂等防御：已有 data 卷标分区则跳过
# 安全边界：只处理根文件系统所在的 mmc 设备；只使用最后一个分区之后的未分配尾部空间（≥1GiB 才动手）

. /lib/functions.sh

log() { logger -t h68k-data -p user.info "$*"; }

# 1) 定位 root 所在物理盘
root="$(sed -n 's/.*root=\([^ ]*\).*/\1/p' /proc/cmdline)"
case "$root" in
	PARTUUID=*)
		puuid="${root#PARTUUID=}"
		rdev="$(blkid -l -t PARTUUID="$puuid" -o device)" ;;
	PARTLABEL=*|/dev/fit*|fit*)
		# MediaTek filogic FIT 布局（BPI-R4 等）：root=/dev/fit0 是 U-Boot 制作的虚拟设备，
		# 真实承载分区为 GPT 的 PARTLABEL=production；eMMC 与 sdcard 同盘
		rdev="$(blkid -l -t PARTLABEL=production -o device)" ;;
	/dev/mmcblk*)
		rdev="$root" ;;
	*)
		exit 0 ;;
esac
[ -n "$rdev" ] || exit 0

case "$rdev" in
	/dev/mmcblk*p[0-9]*) disk="${rdev%p[0-9]*}" ;;	# /dev/mmcblk0p7 -> /dev/mmcblk0
	*) exit 0 ;;					# 非 mmc 分区场景不动
esac
[ -n "$disk" ] || exit 0
[ -b "$disk" ] || exit 0

# 2) 幂等：已存在 data 卷标分区、或 /opt 已有挂载，则退出
#（BPI-R4 从 ImmortalWrt 官方固件转来时可能带着它建的 primary 分区挂在 /opt）
blkid | grep -q 'LABEL="data"' && exit 0
mount | grep -q ' on /opt ' && exit 0

# 3) 计算最后一个分区结束位置（MiB）与磁盘容量
last_end="$(parted -s "$disk" unit MiB print 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {e=int($3)} END{print e}')"
[ -n "$last_end" ] || exit 0
[ "$last_end" -gt 0 ] || exit 0
disk_mib=$(( $(cat "/sys/block/${disk##*/}/size") / 2048 ))
free_mib=$(( disk_mib - last_end ))
if [ "$free_mib" -lt 1024 ]; then
	log "free space ${free_mib}MiB < 1024MiB, skip auto-partition"
	exit 0
fi

# 4) 对最后一个分区之后的未分配空间建分区（GPT）
parted -s "$disk" --align optimal mkpart "primary" "${last_end}MiB" "100%" || { log "parted mkpart failed"; exit 0; }
partprobe "$disk" 2>/dev/null
sleep 2

# 5) 取新建分区号（磁盘上编号最大的分区）
last_num="$(parted -s "$disk" print 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {n=$1} END{print n}')"
[ -n "$last_num" ] || { log "cannot find new partition"; exit 0; }
np="${disk}p${last_num}"
[ -b "$np" ] || { log "$np not present"; exit 0; }

# 6) ext4 格式化（卷标 data）
mkfs.ext4 -F -L data "$np" || { log "mkfs.ext4 $np failed"; exit 0; }

# 7) 写入 fstab 并立即挂载
uuid="$(blkid -s UUID -o value "$np")"
[ -n "$uuid" ] || exit 0
mkdir -p /opt
uci -q delete fstab.data
uci set fstab.data=mount
uci set fstab.data.uuid="$uuid"
uci set fstab.data.target="/opt"
uci set fstab.data.enabled="1"
uci commit fstab
/etc/init.d/fstab restart >/dev/null 2>&1

log "auto-created ${np} (${free_mib}MiB ext4) mounted at /opt"

exit 0
