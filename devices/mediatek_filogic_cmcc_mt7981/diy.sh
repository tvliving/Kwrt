#!/bin/bash
# CMCC RAX3000M / XR30（NAND + eMMC 四机型）注入 —— 全部移植自 tvliving/lede master
#
# 机型方案（与 lede 一致，实测可开机）：
#   NAND：kernel FIT 放 UBI "kernel" 卷 + squashfs 静态卷；出 factory.bin（append-ubi 全量包）
#         与 sysupgrade.bin（sysupgrade-tar，系统内升级）
#   eMMC：kernel / rootfs 两分区 + root=PARTLABEL=rootfs；只出 sysupgrade.bin
#   两类都不产 preloader / fip / gpt，沿用机器现有 U-Boot。
#
# 本脚本注入三处文本；DTS 由 diy/ 目录覆盖（已适配 openwrt-25.12：
#   include 用内核 mt7981b.dtsi，memory 节点补 device_type）
set -e

[ -f target/linux/mediatek/image/filogic.mk ] \
  || { echo "::error::当前目录不是 openwrt 源码树"; exit 1; }

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------------------
# 1) filogic.mk：追加 4 个设备块（lede 原样，只改 DTS 名指向 25.12 适配版 dts）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
if 'define Device/cmcc_rax3000m-nand\n' not in s:
    block = '''
# ============================================================================
# CMCC RAX3000M / XR30（NAND + eMMC），从 tvliving/lede 移植
#  - DTS 见 devices/mediatek_filogic_cmcc_mt7981/diy（已适配 openwrt-25.12）
#  - NAND 出 factory.bin + sysupgrade.bin；eMMC 只出 sysupgrade.bin
#  - 不产 preloader / fip / gpt：沿用机器现有 U-Boot
# ============================================================================

#===== CMCC RAX3000M (eMMC) =====
define Device/cmcc_rax3000m-emmc
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := RAX3000M (eMMC version)
  DEVICE_DTS := mt7981b-cmcc-rax3000m-emmc-lede
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_rax3000m-emmc

#===== CMCC RAX3000M (NAND) =====
define Device/cmcc_rax3000m-nand
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := RAX3000M (NAND version)
  DEVICE_DTS := mt7981b-cmcc-rax3000m-nand-lede
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
TARGET_DEVICES += cmcc_rax3000m-nand

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
'''
    save(p, s + block)
    print('filogic.mk: 已追加 4 个设备块（rax3000m-nand/emmc、xr30-nand/emmc）')
else:
    print('filogic.mk: 设备块已存在，跳过')

final = load(p)
for dev in ('cmcc_rax3000m-emmc', 'cmcc_rax3000m-nand', 'cmcc_xr30-emmc', 'cmcc_xr30-nand'):
    assert 'define Device/%s\n' % dev in final, 'filogic.mk 缺少 %s' % dev
    assert 'TARGET_DEVICES += %s\n' % dev in final, 'filogic.mk 缺少 TARGET_DEVICES += %s' % dev
# 只在「本段注入区」里数 factory，别把 25.12 其它机型的 factory 配方算进来
MARK = '# CMCC RAX3000M / XR30（NAND + eMMC），从 tvliving/lede 移植'
sec = final[final.index(MARK):]
assert sec.count('IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)') == 2, \
    'NAND 的 factory.bin 配方数量异常（应为 2）'
assert sec.count('IMAGES += factory.bin') == 2, 'factory.bin 只该出现在两台 NAND 机型'
assert sec.count('IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata') == 4, \
    '四个机型都该走 sysupgrade-tar'
print('✔ filogic.mk 校验通过（eMMC 只有 sysupgrade，NAND 有 factory + sysupgrade）')

# ---------------------------------------------------------------------------
# 2) platform.sh：eMMC 走 emmc_do_upgrade；两台 eMMC 进 copy_config；
#    四台统一进 ustar(tar) 校验组（NAND 的默认分支本来就是 nand_do_upgrade）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)

EMMC = '\tcmcc,rax3000m-emmc|\\\n\tcmcc,xr30-emmc|\\\n'
ALL4 = ('\tcmcc,rax3000m-emmc|\\\n'
        '\tcmcc,rax3000m-nand|\\\n'
        '\tcmcc,xr30-emmc|\\\n'
        '\tcmcc,xr30-nand|\\\n')

if 'cmcc,rax3000m-emmc' not in s:
    # 2a) platform_do_upgrade 的 emmc 组
    a = '\tglinet,gl-xe3000|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'do_upgrade emmc 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n' + EMMC + '\thiveton,h5000m|\\')

    # 2b) platform_check_image 的 ustar(tar) 组
    a = '\tcreatlentem,clt-r30b1-112m|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'check_image ustar 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tcreatlentem,clt-r30b1-112m|\\\n' + ALL4 + '\thiveton,h5000m|\\')

    # 2c) platform_copy_config 的 emmc 组
    a = '\tglinet,gl-xe3000|\\\n\tglobitel,bt-r320|\\'
    assert s.count(a) == 1, 'copy_config emmc 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n' + EMMC + '\tglobitel,bt-r320|\\')

    save(p, s)
    print('platform.sh: emmc 升级组 + ustar 校验组 + emmc_copy_config 组已加入')
else:
    print('platform.sh: 路由已存在，跳过')

ps = load(p)
assert ps.count('\tcmcc,rax3000m-emmc|') == 3, 'emmc 路由行数量异常: %d' % ps.count('\tcmcc,rax3000m-emmc|')
assert ps.count('\tcmcc,xr30-emmc|') == 3, 'xr30 emmc 路由行数量异常: %d' % ps.count('\tcmcc,xr30-emmc|')
assert ps.count('\tcmcc,rax3000m-nand|') == 1, 'nand 路由行数量异常: %d' % ps.count('\tcmcc,rax3000m-nand|')
assert ps.count('\tcmcc,xr30-nand|') == 1, 'xr30 nand 路由行数量异常: %d' % ps.count('\tcmcc,xr30-nand|')
print('✔ platform.sh 校验通过（eMMC 三处，NAND 仅 ustar 校验组，升级走默认 nand_do_upgrade）')

# ---------------------------------------------------------------------------
# 3) 02_network：LAN/WAN 口映射（lede：lan1 lan2 lan3 + eth1 作 wan）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
s = load(p)

if 'cmcc,rax3000m-nand' not in s:
    a = ('\t*)\n'
         '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n'
         '\t\t;;\n'
         '\tesac\n')
    assert s.count(a) == 1, '02_network 默认 case 锚点异常: %d' % s.count(a)
    block = ('\t# ---- CMCC RAX3000M / XR30（lede 移植）----\n'
             '\tcmcc,rax3000m-emmc|\\\n'
             '\tcmcc,rax3000m-nand|\\\n'
             '\tcmcc,xr30-emmc|\\\n'
             '\tcmcc,xr30-nand)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" eth1\n'
             '\t\t;;\n')
    s = s.replace(a, block + a)
    save(p, s)
    print('02_network: 已加入四机型的 LAN/WAN 映射')
else:
    print('02_network: 机型已存在，跳过')

nw = load(p)
assert nw.count('\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" eth1\n') >= 1
for dev in ('cmcc,rax3000m-emmc', 'cmcc,rax3000m-nand', 'cmcc,xr30-emmc', 'cmcc,xr30-nand'):
    assert dev + '|' in nw or dev + ')' in nw, '02_network 缺少 %s' % dev
print('✔ 02_network 校验通过')
PYEOF

# ---------------------------------------------------------------------------
# 4) 兜底断言（python 段之外再查，防止模板转义把补丁写歪）
# ---------------------------------------------------------------------------
for pat in 'define Device/cmcc_rax3000m-emmc' 'define Device/cmcc_rax3000m-nand' \
           'define Device/cmcc_xr30-emmc' 'define Device/cmcc_xr30-nand'; do
  grep -qF "$pat" target/linux/mediatek/image/filogic.mk \
    || { echo "::error::filogic.mk 缺少: $pat"; exit 1; }
done

[ "$(sed -n '/CMCC RAX3000M \/ XR30（NAND + eMMC），从 tvliving\/lede 移植/,$p' \
        target/linux/mediatek/image/filogic.mk \
      | grep -c 'IMAGE/factory.bin := append-ubi')" -eq 2 ] \
  || { echo "::error::factory.bin 只该给两台 NAND 机型，数量不对"; exit 1; }

for d in mt7981b-cmcc-rax3000m-emmc-lede mt7981b-cmcc-rax3000m-nand-lede \
         mt7981b-cmcc-xr30-emmc mt7981b-cmcc-xr30-nand mt7981b-cmcc-rax3000m-lede \
         mt7981b-cmcc-xr30.dtsi; do
  [ -f "target/linux/mediatek/dts/$d" ] || [ -f "target/linux/mediatek/dts/$d.dts" ] \
    || [ -f "target/linux/mediatek/dts/$d.dtsi" ] \
    || { echo "::error::DTS 缺失: $d"; exit 1; }
done

grep -q 'include "mt7981b-cmcc-rax3000m-lede.dts"' \
  target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-lede.dts \
  || { echo "::error::eMMC dts 未指向 25.12 适配版 base"; exit 1; }
grep -q 'root=PARTLABEL=rootfs' \
  target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-lede.dts \
  || { echo "::error::eMMC dts 缺 root=PARTLABEL=rootfs"; exit 1; }

echo "CMCC RAX3000M / XR30 四机型注入完成（filogic.mk / platform.sh / 02_network）"