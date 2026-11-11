#!/bin/bash
# PHILIPS HY3000 (MT7981B + eMMC) 机型注入
# 方案移植自 tvliving/istoreos istoreos-25.12 分支（已验证的 FIT(itb) 四件套方案）：
#   DTS 与 uboot 补丁由 diy/ 与 patches/ 目录直接覆盖；本脚本完成四处文本注入。
set -e

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# 1) filogic.mk 追加设备块（itb 四件套：sysupgrade.itb + gpt.bin + preloader.bin + bl31-uboot.fip）
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
assert 'philips_hy3000' not in s, 'filogic.mk 已包含 philips_hy3000'
block = '''
define Device/philips_hy3000
  DEVICE_VENDOR := PHILIPS
  DEVICE_MODEL := HY3000
  DEVICE_DTS := mt7981b-philips-hy3000
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_DTS_LOADADDR := 0x43f00000
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \\
\tf2fsck mkf2fs
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  IMAGES := sysupgrade.itb
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
  IMAGE/sysupgrade.itb := append-kernel | \\
\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | \\
\tpad-rootfs | append-metadata
  ARTIFACTS := gpt.bin preloader.bin bl31-uboot.fip
  ARTIFACT/gpt.bin := mt798x-gpt emmc
  ARTIFACT/preloader.bin := mt7981-bl2 emmc-ddr4
  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot philips_hy3000
endef
TARGET_DEVICES += philips_hy3000
'''
save(p, s + block)

# 2) platform.sh 三处组插入（fit_do_upgrade / platform_check_image / platform_copy_config）
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)
a = '\tcmcc,rax3000m|\\\n'
assert s.count(a) == 3, 'platform.sh rax3000m 锚点: %d' % s.count(a)
s = s.replace(a, a + '\tphilips,hy3000|\\\n')
save(p, s)

# 3) envtools（该文件此组无前导 tab）
p = 'package/boot/uboot-tools/uboot-envtools/files/mediatek_filogic'
s = load(p)
a = 'cmcc,rax3000m|\\\njdcloud,re-cp-03)'
assert s.count(a) == 1, 'envtools 锚点: %d' % s.count(a)
s = s.replace(a, 'cmcc,rax3000m|\\\nphilips,hy3000|\\\njdcloud,re-cp-03)')
save(p, s)

# 4) uboot-mediatek Makefile：注册 U-Boot 定义 + UBOOT_TARGETS 条目
p = 'package/boot/uboot-mediatek/Makefile'
s = load(p)
assert 'philips_hy3000' not in s, 'uboot Makefile 已包含 philips_hy3000'
a = 'UBOOT_TARGETS := \\\n'
assert s.count(a) == 1, 'UBOOT_TARGETS 锚点: %d' % s.count(a)
define_block = '''define U-Boot/mt7981_philips_hy3000
  NAME:=PHILIPS HY3000
  BUILD_SUBTARGET:=filogic
  BUILD_DEVICES:=philips_hy3000
  UBOOT_CONFIG:=mt7981_philips_hy3000
  UBOOT_IMAGE:=u-boot.fip
  BL2_BOOTDEV:=emmc
  BL2_SOC:=mt7981
  BL2_DDRTYPE:=ddr4
  DEPENDS:=+trusted-firmware-a-mt7981-emmc-ddr4
endef

'''
s = s.replace(a, define_block + a)
b = '\tmt7981_cmcc_rax3000m-nand-ddr4 \\\n'
assert s.count(b) == 1, 'UBOOT_TARGETS rax3000m-nand-ddr4 锚点: %d' % s.count(b)
s = s.replace(b, b + '\tmt7981_philips_hy3000 \\\n')
save(p, s)

print('HY3000 注入全部完成（filogic.mk / platform.sh x3 / envtools / uboot Makefile）')
PYEOF
