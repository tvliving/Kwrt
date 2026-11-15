#!/bin/bash
# Globitel BT-R320 (MT7981B + MT7531AE + eMMC) 机型改造
#
# 背景：openwrt-25.12 上游已经自带 globitel_bt-r320，但用的是「新 U-Boot」方案：
#       sysupgrade.itb + fitblk（bootargs root=/dev/fit0、rootdisk=<&emmc_rootdisk>），
#       还要先刷 ARTIFACTS 里的 gpt.bin / preloader.bin / bl31-uboot.fip。
#       原厂 U-Boot 无法加载 fit0，itb 也容易被原厂 firmware 分区容量截断，
#       表现就是刷完 rootfs Bad Data Hash 掉进 Web failsafe。
#
# 所以这里按 tvliving/lede 的 globitel_bt-r320 与 Kwrt hy3000 同一套方案改写：
#   内核单独一个 FIT 分区 + rootfs 独立分区 + sysupgrade-tar 升级包，
#   DTS 用 root=PARTLABEL=rootfs 由内核自己找根分区，沿用机器现有 U-Boot。
#
# 具体动作（全部幂等，重复执行安全）：
#   1) filogic.mk：把上游 globitel_bt-r320 设备块换成 sysupgrade-tar 版本
#   2) platform.sh：把 globitel,bt-r320 从 fit_do_upgrade / fit_check_image 组
#      移到 emmc_do_upgrade（CI_KERNPART=kernel / CI_ROOTPART=rootfs）与 tar magic 检查组
#   3) DTS 由 diy/ 覆盖（diy/target/linux/mediatek/dts/mt7981b-globitel-bt-r320.dts）
#   4) 02_network：上游已有 globitel,bt-r320（lan1 lan2 lan3 + wan），无需改动
set -e

python3 - <<'PYEOF'
import io, re, sys

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------------------
# 1) filogic.mk：替换上游设备块
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)

NEW_BLOCK = '''define Device/globitel_bt-r320
  DEVICE_VENDOR := Globitel
  DEVICE_MODEL := BT-R320
  DEVICE_DTS := mt7981b-globitel-bt-r320
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware \\
\tf2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += globitel,bt-r320
endef
TARGET_DEVICES += globitel_bt-r320
'''

m = re.search(r'define Device/globitel_bt-r320\n.*?\nTARGET_DEVICES \+= globitel_bt-r320\n', s, re.S)
if not m:
    sys.exit('filogic.mk: 找不到上游 globitel_bt-r320 设备块（上游结构已变，需人工核对）')

if 'IMAGE/sysupgrade.bin := sysupgrade-tar' in m.group(0):
    print('filogic.mk: 已是 sysupgrade-tar 版本，跳过')
else:
    s = s[:m.start()] + NEW_BLOCK + s[m.end():]
    save(p, s)
    print('filogic.mk: 已替换为 sysupgrade-tar（PARTLABEL rootfs）版本')

# ---------------------------------------------------------------------------
# 2) platform.sh：升级 / 校验分支改走 eMMC tar 流程
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)

ENTRY = '\tglobitel,bt-r320|\\\n'

i_do = s.index('platform_do_upgrade() {')
i_chk = s.index('platform_check_image() {')
i_cp = s.index('platform_copy_config() {')
head, sec_do, sec_chk, sec_cp = s[:i_do], s[i_do:i_chk], s[i_chk:i_cp], s[i_cp:]

if ENTRY not in sec_do:
    print('platform.sh: platform_do_upgrade 已经是 emmc 流程，跳过')
else:
    # 2a) 从 fit_do_upgrade 组摘掉
    assert sec_do.count(ENTRY) == 1, 'platform_do_upgrade 里 globitel 条目数量异常: %d' % sec_do.count(ENTRY)
    sec_do = sec_do.replace(ENTRY, '', 1)

    # 2b) 挂到 emmc 组（锚点：该组最后一项 smartrg,sdg-8734) + CI_KERNPART）
    a = '\tsmartrg,sdg-8734)\n\t\tCI_KERNPART="kernel"\n\t\tCI_ROOTPART="rootfs"\n\t\temmc_do_upgrade "$1"\n'
    assert sec_do.count(a) == 1, 'platform.sh emmc 组锚点异常: %d' % sec_do.count(a)
    sec_do = sec_do.replace(a, ENTRY + a, 1)

    # 2c) 从 fit_check_image 组摘掉
    assert sec_chk.count(ENTRY) == 1, 'platform_check_image 里 globitel 条目数量异常: %d' % sec_chk.count(ENTRY)
    sec_chk = sec_chk.replace(ENTRY, '', 1)

    # 2d) 挂到 tar magic（ustar）检查组
    b = '\tcreatlentem,clt-r30b1|\\\n\tcreatlentem,clt-r30b1-112m|\\\n'
    assert sec_chk.count(b) == 1, 'platform.sh tar 检查组锚点异常: %d' % sec_chk.count(b)
    sec_chk = sec_chk.replace(b, ENTRY + b, 1)

    save(p, head + sec_do + sec_chk + sec_cp)
    print('platform.sh: globitel,bt-r320 → emmc_do_upgrade + tar magic 校验')

assert ENTRY in sec_cp, 'platform_copy_config 里没有 globitel,bt-r320（上游结构已变）'
print('platform.sh: platform_copy_config 已是 emmc_copy_config，无需改动')
print('BT-R320 改造完成（filogic.mk + platform.sh；DTS 由 diy/ 覆盖）')
PYEOF
