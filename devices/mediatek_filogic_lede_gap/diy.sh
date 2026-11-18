#!/bin/bash
# 从 lede / immortalwrt-mt798x 移植到 Kwrt 的机型注入
#   1) imou_lc-hx3001      lede master            mt7981b  NAND+UBI  sysupgrade-tar
#   2) tenda_be12-pro      lede master            mt7987a  NAND+UBI  tenda 双镜像头 + tar
#   3) tplink_wma301       immortalwrt-mt798x-6.6 mt7981b  NAND+UBI  factory + tar
#   4) tplink_wma301-stock  同上（stock 分区）      mt7981b  只出 sysupgrade
#   5) tplink_wma301_2.1    同上（2.1 版 stock）    mt7981b  只出 sysupgrade
#   6) tplink_wma301-ubootmod 同上（OpenWrt 分区）  mt7981b  fitblk itb
#
# 全部不产 preloader / fip / gpt 引导工件（沿用机器现有 U-Boot）。
# stock / 2.1 的 factory.bin 需过 64MB check-size，带 iStore + 全量中文包必超，
# 故只出 sysupgrade（首刷请用原厂/ImmortalWrt 的 factory）。
set -e

python3 - <<'PYEOF'
import io


def load(p):
    return io.open(p, encoding='utf-8', newline='').read()


def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# ---------------------------------------------------------------------------
# 1) filogic.mk：追加 Build 宏 + 6 个设备块
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)

if 'imou_lc-hx3001' not in s:
    block = '''
# ============================================================================
# 移植机型（2026-11-18）：lede 独有机型 + immortalwrt-mt798x 的 WMA301
#  - DTS 由 devices/mediatek_filogic_lede_gap/diy 覆盖（已适配 25.12 include）
#  - 不产 preloader / fip / gpt
# ============================================================================

#===== Tenda BE12 Pro 双镜像头（lede filogic.mk 同名 Build 宏）=====
define Build/tenda-mkdualimageheader
	printf '%b' "\\x47\\x6f\\x64\\x31\\x00\\x00\\x00\\x00" >"$@.new"
	gzip -c "$@" | tail -c8 >>"$@.new"
	cat "$@" >>"$@.new"
	mv "$@.new" "$@"
endef

#===== IMOU LC-HX3001 =====
define Device/imou_lc-hx3001
  DEVICE_VENDOR := IMOU
  DEVICE_MODEL := LC-HX3001
  DEVICE_DTS := mt7981b-imou-lc-hx3001
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += imou_lc-hx3001

#===== Tenda BE12 Pro =====
define Device/tenda_be12-pro
  DEVICE_VENDOR := Tenda
  DEVICE_MODEL := BE12 Pro
  DEVICE_DTS := mt7987a-tenda-be12-pro
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := mt7987-2p5g-phy-firmware airoha-en8811h-firmware kmod-phy-airoha-en8811h kmod-phy-mediatek-2p5g kmod-mt7992-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_LOADADDR := 0x40000000
  IMAGE/sysupgrade.bin := append-kernel | tenda-mkdualimageheader | sysupgrade-tar kernel=$$$$@ | append-metadata
endef
TARGET_DEVICES += tenda_be12-pro

#===== TP-Link WMA301（默认布局，114MB 分区，保留 factory）=====
define Device/tplink_wma301
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := WMA301
  DEVICE_DTS := mt7981b-tplink-wma301
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += mediatek,mt7981-spim-snand-rfb
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  KERNEL = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd
endef
TARGET_DEVICES += tplink_wma301

#===== TP-Link WMA301 stock 布局（64MB 分区，factory 装不下全家桶，只出 sysupgrade）=====
define Device/tplink_wma301-stock
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := WMA301
  DEVICE_VARIANT := (stock layout)
  DEVICE_DTS := mt7981b-tplink-wma301-stock
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += mediatek,mt7981-spim-snand-rfb
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  KERNEL = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd
endef
TARGET_DEVICES += tplink_wma301-stock

#===== TP-Link WMA301 2.1（64MB 分区，同上只出 sysupgrade）=====
define Device/tplink_wma301_2.1
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := WMA301 2.1
  DEVICE_VARIANT := (stock layout)
  DEVICE_DTS := mt7981b-tplink-wma301_2.1
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += mediatek,mt7981-spim-snand-rfb
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  KERNEL = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS = kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd
endef
TARGET_DEVICES += tplink_wma301_2.1

#===== TP-Link WMA301 OpenWrt 布局（fitblk itb，不产引导工件）=====
define Device/tplink_wma301-ubootmod
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := WMA301
  DEVICE_VARIANT := (OpenWrt layout)
  DEVICE_DTS := mt7981b-tplink-wma301-ubootmod
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += tplink,wma301 mediatek,mt7981
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
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
\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata
endef
TARGET_DEVICES += tplink_wma301-ubootmod
'''
    s = s + block
    save(p, s)
    print('filogic.mk: 已追加 6 个设备块 + tenda 双镜像头')
else:
    print('filogic.mk: 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 2) platform.sh：tar 机型进 UBI 升级组，wma301-ubootmod 进 fit 组
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)

if 'imou,lc-hx3001' not in s:
    a = '\thuasifei,wh3000r-nand|\\\n\tjiorouter,ax6000-jidu6101|\\'
    assert s.count(a) == 1, 'platform.sh UBI 组锚点异常: %d' % s.count(a)
    ins = ('\timou,lc-hx3001|\\\n'
           '\ttenda,be12-pro|\\\n'
           '\ttplink,wma301|\\\n'
           '\ttplink,wma301-stock|\\\n'
           '\ttplink,wma301_2.1|\\\n')
    s = s.replace(a, '\thuasifei,wh3000r-nand|\\\n' + ins + '\tjiorouter,ax6000-jidu6101|\\')

    a = '\ttplink,tl-xtr8488|\\\n\twavlink,wl-wnt100x3-ubootmod|\\'
    # 该列表在 platform_do_upgrade 的 fit 组和 platform_check_image 的 fit 校验组各出现一次，两处都要加
    assert s.count(a) == 2, 'platform.sh fit 组锚点异常: %d' % s.count(a)
    s = s.replace(a, '\ttplink,tl-xtr8488|\\\n\ttplink,wma301-ubootmod|\\\n\twavlink,wl-wnt100x3-ubootmod|\\')

    # tar（ustar）镜像校验组：不加的话 platform_check_image 会拒绝 tar 包
    a = ('\tcreatlentem,clt-r30b1|\\\n'
         '\tcreatlentem,clt-r30b1-112m|\\\n'
         '\thiveton,h5000m|\\')
    assert s.count(a) == 1, 'platform.sh ustar 校验组锚点异常: %d' % s.count(a)
    s = s.replace(a, a + '\n'
                     '\timou,lc-hx3001|\\\n'
                     '\ttenda,be12-pro|\\\n'
                     '\ttplink,wma301|\\\n'
                     '\ttplink,wma301-stock|\\\n'
                     '\ttplink,wma301_2.1|\\')

    save(p, s)
    print('platform.sh: UBI 组 + fit 组已加入')
else:
    print('platform.sh: 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 3) 02_network：接口映射 + imou 的 MAC 规则
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
s = load(p)

if 'imou,lc-hx3001' not in s:
    # 3a) imou,lc-hx3001 与 imou,hx21 同组（lan1-3 + eth1）
    a = '\timou,hx21|\\\n'
    assert s.count(a) == 1, '02_network imou,hx21 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\timou,lc-hx3001|\\\n' + a)

    # 3b) tenda / wma301 单独 case，必须插在 setup_interfaces 的 `*)` 默认分支之前
    #     （shell case 顺序匹配，放 *) 之后永远不会命中）
    a = ('\t*)\n'
         '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n')
    assert s.count(a) == 1, '02_network 默认 case 锚点异常: %d' % s.count(a)
    block = ('\ttenda,be12-pro)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan3 lan4 lan5 eth1" eth2\n'
             '\t\t;;\n'
             '\ttplink,wma301*)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n'
             '\t\t;;\n')
    s = s.replace(a, block + a)

    # 3c) imou MAC：factory 取自 u-boot-env，wan = lan + 2（与 lede 一致）
    a = '\tqihoo,360t7)\n\t\tlan_mac=$(mtd_get_mac_ascii factory lanMac)'
    assert s.count(a) == 1, '02_network MAC 段锚点异常: %d' % s.count(a)
    s = s.replace(a, '\timou,lc-hx3001)\n'
                     '\t\tlan_mac=$(mtd_get_mac_ascii u-boot-env mac)\n'
                     '\t\twan_mac=$(macaddr_add "$lan_mac" 2)\n'
                     '\t\tlabel_mac=$lan_mac\n'
                     '\t\t;;\n' + a)

    save(p, s)
    print('02_network: 接口映射 + MAC 规则已加入')
else:
    print('02_network: 机型已存在，跳过')

print('移植机型注入完成')
PYEOF
