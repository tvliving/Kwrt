#!/bin/bash
# MT798x 其余机型（从 tvliving/lede 移植的 15 个设备块）注入
#
# 与 tvliving/lede master 的机型方案一致（该方案实测可正常开机）：
#   NAND/UBI 机型：kernel FIT 放 UBI 卷 + sysupgrade-tar；eMMC 机型：
#   emmc 分区 kernel+rootfs + sysupgrade-tar；7DR7299：fitblk itb。
#   不编译、不替换 preloader / fip / U-Boot，产物无引导工件。
#
# 本脚本完成四处文本注入；DTS 由 diy/ 目录覆盖（已适配 openwrt-25.12：
#   include 用内核提供的 mt7981b.dtsi，memory 节点补 device_type）。
set -e

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------------------
# 1) filogic.mk：追加 15 个设备块（lede 同款；7dr7299 内联 tplink-tl-7dr-common，
#    25.12 没有该 define，不产出引导工件）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
if 'cetron_ct3003-mod' not in s:
    block = '''
# ============================================================================
# 从 tvliving/lede 移植的机型（openwrt-25.12 上游没有的）
#  - DTS 由 devices/mediatek_filogic_mt798x_other/diy 覆盖（含 25.12 适配）
#  - 7dr7299 内联 lede/x-wrt 的 tplink-tl-7dr-common 出包方案（fitblk itb），
#    lede 版 ARTIFACT(preloader/bl31) 依赖 lede 特有 ATF combo，不产出引导工件
# ============================================================================

#===== Cetron CT3003 (U-Boot mod) =====
define Device/cetron_ct3003-mod
  DEVICE_VENDOR := Cetron
  DEVICE_MODEL := CT3003 (U-Boot mod)
  DEVICE_DTS := mt7981b-cetron-ct3003-mod
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cetron_ct3003-mod

#===== CLX S20L =====
define Device/clx_s20l
  DEVICE_VENDOR := CLX
  DEVICE_MODEL := S20L
  DEVICE_DTS := mt7986a-clx-s20l
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := e2fsprogs f2fsck mkf2fs kmod-usb3 \\
\tkmod-mt7986-firmware mt7986-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += clx_s20l

#===== CMCC A10 (U-Boot mod) =====
define Device/cmcc_a10-mod
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := A10 (U-Boot mod)
  DEVICE_DTS := mt7981b-cmcc-a10-mod
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware
endef
TARGET_DEVICES += cmcc_a10-mod

#===== CMCC RAX3000Me (eMMC) =====
define Device/cmcc_rax3000me-emmc
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := RAX3000Me (eMMC version)
  DEVICE_DTS := mt7981b-cmcc-rax3000me
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_rax3000me-emmc

#===== CMCC RAX3000Me (NAND) =====
define Device/cmcc_rax3000me-nand
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := RAX3000Me (NAND version)
  DEVICE_DTS := mt7981b-cmcc-rax3000me
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_OVERLAY := mt7981b-cmcc-rax3000me-nousb
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_rax3000me-nand

#===== CMCC XR30 (eMMC) =====
define Device/cmcc_xr30-emmc
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 (eMMC version)
  DEVICE_DTS := mt7981b-cmcc-xr30-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30-emmc

#===== CMCC XR30 (NAND, U-Boot mod) =====
define Device/cmcc_xr30-nand
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 NAND
  DEVICE_VARIANT := (U-Boot mod)
  DEVICE_DTS := mt7981b-cmcc-xr30-nand
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30-nand

#===== Cudy TR3000 (U-Boot mod) =====
define Device/cudy_tr3000-mod
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := (U-Boot mod)
  DEVICE_DTS := mt7981b-cudy-tr3000-mod
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7981-firmware mt7981-wo-firmware
endef
TARGET_DEVICES += cudy_tr3000-mod

#===== FZS 5GCPE P3 =====
define Device/fzs_5gcpe-p3
  DEVICE_VENDOR := FZS
  DEVICE_MODEL := 5GCPE P3
  DEVICE_DTS := mt7981b-fzs-5gcpe-p3
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += fzs_5gcpe-p3

#===== HF M7986R1 (eMMC) =====
define Device/hf_m7986r1-emmc
  DEVICE_VENDOR := HF
  DEVICE_MODEL := M7986R1 (eMMC)
  DEVICE_DTS := mt7986a-hf-m7986r1-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7921e kmod-usb-net-rndis kmod-usb-serial-option f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += HF-M7986R1
endef
TARGET_DEVICES += hf_m7986r1-emmc

#===== HF M7986R1 (NAND) =====
define Device/hf_m7986r1-nand
  DEVICE_VENDOR := HF
  DEVICE_MODEL := M7986R1 (NAND)
  DEVICE_DTS := mt7986a-hf-m7986r1-nand
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7921e kmod-usb-net-rndis kmod-usb-serial-option
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += HF-M7986R1
endef
TARGET_DEVICES += hf_m7986r1-nand

#===== Huasifei WS3006 =====
define Device/huasifei_ws3006
  DEVICE_VENDOR := Huasifei
  DEVICE_MODEL := WS3006
  DEVICE_DTS := mt7981b-huasifei-ws3006
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 112640k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += huasifei_ws3006

#===== Huasifei WS3009 =====
define Device/huasifei_ws3009
  DEVICE_VENDOR := Huasifei
  DEVICE_MODEL := WS3009
  DEVICE_DTS := mt7981b-huasifei-ws3009
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 112640k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += huasifei_ws3009

#===== JDCloud RE-CS-05 (AX6000 Pro) =====
define Device/jdcloud_re-cs-05
  DEVICE_VENDOR := JDCloud
  DEVICE_MODEL := AX6000 Pro
  DEVICE_DTS := mt7986a-jdcloud-re-cs-05
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := e2fsprogs f2fsck mkf2fs kmod-mt7986-firmware mt7986-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += jdcloud_re-cs-05

#===== TP-Link TL-7DR7299 v1（fitblk itb，无引导工件）=====
define Device/tplink_tl-7dr7299-v1
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := TL-7DR7299
  DEVICE_VARIANT := v1
  DEVICE_DTS := mt7988a-tplink-tl-7dr7299-v1
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | \\
\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | append-metadata
  DEVICE_PACKAGES := kmod-mt7992-firmware mt7988-wo-firmware kmod-sfp kmod-usb3
  KERNEL_LOADADDR := 0x48000000
endef
TARGET_DEVICES += tplink_tl-7dr7299-v1
'''
    save(p, s + block)
    print('filogic.mk: 已追加 15 个机型设备块')
else:
    print('filogic.mk: 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 2) platform.sh：升级/校验/配置分组（对齐 lede）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)

if 'tplink,tl-7dr7299-v1' not in s:
    # 2a) platform_do_upgrade fit 组（25.12 锚点：zyxel,wx5600-t0-ubootmod -> fit_do_upgrade）
    a = '\tzyxel,wx5600-t0-ubootmod)\n\t\tfit_do_upgrade "$1"'
    assert s.count(a) == 1, 'platform.sh fit_do_upgrade 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\ttplink,tl-7dr7299-v1|\\\n' + a)

    # 2b) platform_do_upgrade emmc 组（对齐 lede，5 台 eMMC 设备）
    a = '\tglinet,gl-xe3000|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'platform.sh do_upgrade emmc 锚点异常: %d' % s.count(a)
    ins = ('\tcmcc,rax3000me-emmc|\\\n'
           '\tcmcc,xr30-emmc|\\\n'
           '\tclx,s20l|\\\n'
           '\thf,m7986r1-emmc|\\\n'
           '\tjdcloud,re-cs-05|\\\n')
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n' + ins + '\thiveton,h5000m|\\')

    # 2c) platform_check_image fit 组
    a = '\tzyxel,ex5601-t0-ubootmod)\n\t\tfit_check_image "$1"'
    assert s.count(a) == 1, 'platform.sh fit_check_image 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\ttplink,tl-7dr7299-v1|\\\n' + a)

    # 2d) platform_check_image ustar(tar) 组
    a = '\tcreatlentem,clt-r30b1-112m|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'platform.sh ustar 校验组锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tcreatlentem,clt-r30b1-112m|\\\n' + ins + '\thiveton,h5000m|\\')

    # 2e) platform_copy_config emmc 组
    a = '\tglinet,gl-xe3000|\\\n\tglobitel,bt-r320|\\'
    assert s.count(a) == 1, 'platform.sh copy_config emmc 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n' + ins + '\tglobitel,bt-r320|\\')

    save(p, s)
    print('platform.sh: fit/emmc 升级组 + ustar 校验组 + emmc_copy_config 组已加入')
else:
    print('platform.sh: 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 3) 02_network：LAN/WAN 口映射 + MAC 地址来源
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
s = load(p)

if 'cetron,ct3003-mod' not in s:
    # 3a) 接口映射：插在 setup_interfaces 的默认 case 之前
    a = ('\t*)\n'
         '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n'
         '\t\t;;\n'
         '\tesac\n')
    assert s.count(a) == 1, '02_network setup_interfaces 默认 case 锚点异常: %d' % s.count(a)
    block = ('\t# ---- 以下为从 tvliving/lede 移植的机型 ----\n'
             '\tcetron,ct3003-mod|\\\n'
             '\tcmcc,a10-mod|\\\n'
             '\tfzs,5gcpe-p3)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n'
             '\t\t;;\n'
             '\tcmcc,rax3000me-emmc|\\\n'
             '\tcmcc,rax3000me-nand|\\\n'
             '\tcmcc,xr30-emmc|\\\n'
             '\tcmcc,xr30-nand)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" eth1\n'
             '\t\t;;\n'
             '\tcudy,tr3000-mod)\n'
             '\t\tucidef_set_interfaces_lan_wan eth1 eth0\n'
             '\t\t;;\n'
             '\thuasifei,ws3006)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 eth1" "wan"\n'
             '\t\t;;\n'
             '\thuasifei,ws3009|\\\n'
             '\tjdcloud,re-cs-05)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" eth1\n'
             '\t\t;;\n'
             '\thf,m7986r1-emmc|\\\n'
             '\thf,m7986r1-nand)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan2 lan3 lan4" "lan1 usb0"\n'
             '\t\t;;\n'
             '\ttplink,tl-7dr7299-v1)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4 lan5 lan6 sfp" "eth1"\n'
             '\t\t;;\n')
    s = s.replace(a, block + a)

    # 3b) MAC：jdcloud re-cs-05 factory 0x24/0x2a（与 lede 一致）
    a = '''\tqihoo,360t7)
\t\tlan_mac=$(mtd_get_mac_ascii factory lanMac)
'''
    assert s.count(a) == 1, '02_network mac 段锚点数量异常: %d' % s.count(a)
    s = s.replace(a, '''\tjdcloud,re-cs-05)
\t\twan_mac=$(mmc_get_mac_binary factory 0x24)
\t\tlan_mac=$(mmc_get_mac_binary factory 0x2a)
\t\tlabel_mac=$lan_mac
\t\t;;
''' + a)
    save(p, s)
    print('02_network: 已加入接口映射与 MAC 规则')
else:
    print('02_network: 机型已存在，跳过')

print('MT798x 其他机型注入完成（filogic.mk / platform.sh / 02_network）')
PYEOF
