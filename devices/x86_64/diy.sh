#!/bin/bash

SHELL_FOLDER=$(dirname $(readlink -f "$0"))

#bash $SHELL_FOLDER/../common/kernel_6.6.sh

sed -i 's/Os/O2/g' include/target.mk

git_clone_path master https://github.com/coolsnowwolf/lede target/linux/x86/files target/linux/x86/patches-6.12

wget -N https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/x86/base-files/etc/board.d/02_network -P target/linux/x86/base-files/etc/board.d/
wget -N https://github.com/coolsnowwolf/lede/raw/refs/heads/master/target/linux/x86/Makefile -P target/linux/x86/
sed -i -e "s/ autocore-x86//" \
	   -e "s/ usb-net-rtl8152-vendor/usb-net-rtl8152/" \
       -e "s/ automount//" \
	   -e "s/6.18/6.12/" target/linux/x86/Makefile

sed -i 's/kmod-r8169/kmod-r8168/' target/linux/x86/image/64.mk

sed -i 's/256/1024/g' target/linux/x86/image/Makefile

# lede 版 Makefile 声明 KERNEL_TESTING_PATCHVER=7.3，25.12 无 kernel-7.3 hash 文件，
# target 扫描失败导致 x86 target 丢失（run 43352017892）
sed -i '/KERNEL_TESTING_PATCHVER/d' target/linux/x86/Makefile
# 补回 25.12 原生 features（lede 版没有 ext4/targz，CONFIG_TARGET_ROOTFS_TARGZ 会被丢）
sed -i 's/FEATURES:=squashfs/FEATURES:=squashfs ext4 targz/' target/linux/x86/Makefile
