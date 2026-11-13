#!/bin/bash

SHELL_FOLDER=$(dirname $(readlink -f "$0"))

#bash $SHELL_FOLDER/../common/kernel_6.6.sh

sed -i 's/Os/O2/g' include/target.mk

git_clone_path master https://github.com/coolsnowwolf/lede target/linux/x86/files target/linux/x86/patches-6.12

wget -N https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/x86/base-files/etc/board.d/02_network -P target/linux/x86/base-files/etc/board.d/
# lede master 的 x86/Makefile 与 25.12 不兼容（KERNEL_TESTING_PATCHVER=7.3 无 kernel-7.3 hash 文件，
# target 元数据扫描失败，.config 丢失 CONFIG_TARGET_x86_64 → run 43352017892 两次失败）。
# 不再覆盖 Makefile，改为在 25.12 原生 Makefile 上注入 lede 的网卡/外设驱动包。
sed -i 's/^DEFAULT_PACKAGES += /DEFAULT_PACKAGES += kmod-atlantic kmod-bnx2x kmod-i40e kmod-iavf kmod-igb kmod-igbvf kmod-igc kmod-e1000e kmod-pcnet32 kmod-tulip kmod-via-velocity kmod-vmxnet3 kmod-sound-hda-core kmod-sound-hda-codec-realtek kmod-sound-hda-codec-via kmod-sound-via82xx kmod-sound-hda-intel kmod-sound-hda-codec-hdmi kmod-sound-i8x0 kmod-usb-net kmod-usb-net-aqc111 kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 kmod-mlx4-core kmod-mlx5-core kmod-drm-i915 kmod-drm-amdgpu kmod-usb-audio kmod-8139cp kmod-8139too kmod-tg3 lm-sensors /' target/linux/x86/Makefile

sed -i 's/kmod-r8169/kmod-r8168/' target/linux/x86/image/64.mk

sed -i 's/256/1024/g' target/linux/x86/image/Makefile

# lede 版 Makefile 声明 KERNEL_TESTING_PATCHVER=7.3，25.12 无 kernel-7.3 hash 文件，
# target 扫描失败导致 x86 target 丢失（run 43352017892）
sed -i '/KERNEL_TESTING_PATCHVER/d' target/linux/x86/Makefile
# 补回 25.12 原生 features（lede 版没有 ext4/targz，CONFIG_TARGET_ROOTFS_TARGZ 会被丢）
sed -i 's/FEATURES:=squashfs/FEATURES:=squashfs ext4 targz/' target/linux/x86/Makefile
