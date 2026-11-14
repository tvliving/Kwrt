#!/bin/bash
# PHILIPS HY3000 (MT7981B + MT7531 + eMMC) 机型注入
#
# 方案与 tvliving/lede master 的 philips_hy3000 完全一致（该方案实测可正常开机）：
#   内核单独一个 FIT 分区 + rootfs 独立分区 + sysupgrade-tar 升级包，
#   DTS 用 root=PARTLABEL=rootfs 由内核自己找根分区，不依赖 U-Boot 传参。
#
# 不再使用「FIT external-static-with-rootfs + preloader/fip/gpt 四件套」方案：
#   原厂 U-Boot 无法加载 fit0，且 itb 超过原厂 firmware 分区容量会被截断，
#   表现为开机 rootfs Bad Data Hash 后掉进 Web failsafe。
#
# DTS 由 diy/ 目录覆盖；本脚本完成三处文本注入。
set -e

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------------------
# 1) filogic.mk：追加设备块（lede 同款：FIT 内核 + sysupgrade-tar，无 ARTIFACTS）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
if 'philips_hy3000' not in s:
    block = '''
define Device/philips_hy3000
  DEVICE_VENDOR := Philips
  DEVICE_MODEL := HY3000
  DEVICE_DTS := mt7981b-philips-hy3000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware \\
\tkmod-usb3 f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += philips,hy3000
endef
TARGET_DEVICES += philips_hy3000
'''
    save(p, s + block)
    print('filogic.mk: 已追加 philips_hy3000')
else:
    print('filogic.mk: philips_hy3000 已存在，跳过')

# ---------------------------------------------------------------------------
# 2) platform.sh：加入 eMMC 升级组（platform_do_upgrade + platform_copy_config）
#    锚点 airpi,ap3000m 恰好在两处 emmc 组里各出现一次，全部替换即可
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)
if 'philips,hy3000' not in s:
    a = '\tairpi,ap3000m|\\\n'
    n = s.count(a)
    assert n == 2, 'platform.sh airpi,ap3000m 锚点数量异常: %d（上游结构已变，需人工核对）' % n
    s = s.replace(a, a + '\tphilips,hy3000|\\\n')
    save(p, s)
    print('platform.sh: 已加入 emmc_do_upgrade / emmc_copy_config 两组')
else:
    print('platform.sh: philips,hy3000 已存在，跳过')

# ---------------------------------------------------------------------------
# 3) 02_network：LAN/WAN 口映射 + MAC 地址来源
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
s = load(p)

if 'philips,hy3000' not in s:
    # 3a) lan1 lan2 lan3 + wan（MT7531 三个 LAN 口）
    a = '''\trouterich,ax3000|\\
\trouterich,ax3000-ubootmod|\\
\trouterich,be7200|\\
\ttenbay,wr3000k|\\
\tteralink,tl3020-256mb)
\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan
'''
    assert s.count(a) == 1, '02_network lan/wan 组锚点数量异常: %d' % s.count(a)
    s = s.replace(a, a.replace('\trouterich,ax3000|\\\n',
                               '\tphilips,hy3000|\\\n\trouterich,ax3000|\\\n', 1))

    # 3b) MAC：factory 分区 0x74 为 LAN，WAN = LAN + 1（与 lede 一致）
    a = '''\tqihoo,360t7)
\t\tlan_mac=$(mtd_get_mac_ascii factory lanMac)
'''
    assert s.count(a) == 1, '02_network mac 段锚点数量异常: %d' % s.count(a)
    s = s.replace(a, '''\tphilips,hy3000)
\t\tlan_mac=$(mmc_get_mac_binary factory 0x74)
\t\twan_mac=$(macaddr_add "$lan_mac" 1)
\t\tlabel_mac=$wan_mac
\t\t;;
''' + a)
    save(p, s)
    print('02_network: 已加入 interface 映射与 MAC 规则')
else:
    print('02_network: philips,hy3000 已存在，跳过')

print('HY3000 注入完成（filogic.mk / platform.sh / 02_network）')
PYEOF
