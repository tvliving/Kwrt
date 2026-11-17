#!/bin/bash
# iKuai Q3000 (MT7981) + Q6000 (MT7986A NAND/eMMC) 设备注入
#
# 设备来源：
#   - Q6000：dailook/immortalwrt-24.10（DTS 原样，24.10 主线风格，
#     内核 6.x 的 nvmem mac-base / mediatek,nmbm 绑定，25.12 兼容）
#   - Q3000：XIAOZHAOXSXH/Build-IK-Q3000-ImmortalWrt-MT798x（21.02 SDK
#     风格 DTS 需重写；本移植按 25.12 主线骨架重写为 mt7981b-ikuai-q3000，
#     分区/MAC/LED/按键保留原厂值，去 SDK 专有的 nmbm/hnat/trng 节点）
#
# 升级方案（不编译引导工件）：
#   Q3000 / Q6000(NAND)：KERNEL_IN_UBI + sysupgrade-tar，走 fit 组
#   Q6000(eMMC)：sysupgrade-tar，走 emmc 组
#
# 本脚本完成四处文本注入；DTS 由 diy/ 目录覆盖。
set -e

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------------------------------------------------------------------
# 1) filogic.mk：追加 3 个设备块
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
if 'ikuai_q6000' not in s:
    block = '''
# ============================================================================
# iKuai IK-Q3000 / IK-Q6000（自 XIAOZHAOXSXH / dailook 移植）
#  - DTS 由 devices/mediatek_filogic_ikuai/diy 覆盖
#  - 不产出 preloader / bl31 / gpt 引导工件
# ============================================================================

#===== iKuai Q3000 (SPI-NAND, FIT) =====
define Device/ikuai_q3000
  DEVICE_VENDOR := iKuai
  DEVICE_MODEL := Q3000
  DEVICE_DTS := mt7981b-ikuai-q3000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114816k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ikuai_q3000

#===== iKuai Q6000 (NAND) =====
define Device/ikuai_q6000
  DEVICE_VENDOR := iKuai
  DEVICE_MODEL := Q6000
  DEVICE_DTS := mt7986a-ikuai-q6000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-mtd-rw
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ikuai_q6000

#===== iKuai Q6000 (eMMC) =====
define Device/ikuai_q6000-emmc
  DEVICE_VENDOR := iKuai
  DEVICE_MODEL := Q6000 (eMMC)
  DEVICE_DTS := mt7986a-ikuai-q6000-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-mtd-rw \\
\tcoremark blkid blockdev fdisk f2fsck mkf2fs kmod-mmc \\
\tluci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-server
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ikuai_q6000-emmc

'''
    # 注意：不能 rfind('endif') 插入！filogic.mk 末尾是 zyxel_wx5600 块内的
    # ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),) 条件，rfind 会插进条件块内部，
    # 普通构建整段被跳过（x-wrt run 44012827769 实证 15 != 18）。必须追加到
    # 文件真正末尾（顶层作用域）。
    if not s.endswith('\n'):
        s += '\n'
    s = s.rstrip('\n') + '\n\n' + block.rstrip('\n') + '\n'
    save(p, s)
    print('filogic.mk: 已追加 3 个 ikuai 设备块')
else:
    print('filogic.mk: ikuai 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 2) platform.sh：升级/校验/配置分组
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
s = load(p)

if 'ikuai,q6000' not in s:
    # 2a) platform_do_upgrade fit 组（Q3000 / Q6000 NAND）
    a = '\tzyxel,wx5600-t0-ubootmod)\n\t\tfit_do_upgrade "$1"'
    assert s.count(a) == 1, 'platform.sh fit_do_upgrade 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tikuai,q3000|\\\n\tikuai,q6000|\\\n' + a)

    # 2b) platform_do_upgrade emmc 组（Q6000 eMMC）
    a = '\tglinet,gl-xe3000|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'platform.sh do_upgrade emmc 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n\tikuai,q6000-emmc|\\\n\thiveton,h5000m|\\')

    # 2c) platform_check_image fit 组
    a = '\tzyxel,ex5601-t0-ubootmod)\n\t\tfit_check_image "$1"'
    assert s.count(a) == 1, 'platform.sh fit_check_image 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tikuai,q3000|\\\n\tikuai,q6000|\\\n' + a)

    # 2d) platform_check_image ustar(tar) 组
    a = '\tcreatlentem,clt-r30b1-112m|\\\n\thiveton,h5000m|\\'
    assert s.count(a) == 1, 'platform.sh ustar 校验组锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tcreatlentem,clt-r30b1-112m|\\\n\tikuai,q6000-emmc|\\\n\thiveton,h5000m|\\')

    # 2e) platform_copy_config emmc 组
    a = '\tglinet,gl-xe3000|\\\n\tglobitel,bt-r320|\\'
    assert s.count(a) == 1, 'platform.sh copy_config emmc 锚点异常: %d' % s.count(a)
    s = s.replace(a, '\tglinet,gl-xe3000|\\\n\tikuai,q6000-emmc|\\\n\tglobitel,bt-r320|\\')

    save(p, s)
    print('platform.sh: fit(Q3000/Q6000) + emmc(Q6000-eMMC) 分组已加入')
else:
    print('platform.sh: ikuai 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 3) 02_network：LAN/WAN 口映射 + MAC 地址来源
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'
s = load(p)

if 'ikuai,q3000' not in s:
    # 3a) 接口映射：插在 mediatek_setup_interfaces 默认 case 之前
    a = ('\t*)\n'
         '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n'
         '\t\t;;\n'
         '\tesac\n')
    assert s.count(a) == 1, '02_network setup_interfaces 默认 case 锚点异常: %d' % s.count(a)
    block = ('\tikuai,q3000)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n'
             '\t\t;;\n'
             '\tikuai,q6000-emmc|\\\n'
             '\tikuai,q6000)\n'
             '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" eth1\n'
             '\t\t;;\n')
    s = s.replace(a, block + a)

    # 3b) MAC：Q3000 wan=Factory 0x10048，lan=wan+1；Q6000 的 MAC 由
    #     DTS nvmem(macaddr_factory_4 + addend) 处理，无需 02_network 规则
    a = '''\tqihoo,360t7)
\t\tlan_mac=$(mtd_get_mac_ascii factory lanMac)
'''
    assert s.count(a) == 1, '02_network mac 段锚点数量异常: %d' % s.count(a)
    s = s.replace(a, '''\tikuai,q3000)
\t\twan_mac=$(mtd_get_mac_binary factory 0x10048)
\t\tlan_mac=$(macaddr_add $wan_mac 1)
\t\t;;
''' + a)
    save(p, s)
    print('02_network: 已加入 ikuai 接口映射与 MAC 规则')
else:
    print('02_network: ikuai 机型已存在，跳过')

# ---------------------------------------------------------------------------
# 4) 01_leds：Q3000 三色状态灯
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/filogic/base-files/etc/board.d/01_leds'
s = load(p)

if 'ikuai,q3000' not in s:
    a = 'case $board in\n'
    assert s.count(a) == 1, '01_leds case 锚点异常: %d' % s.count(a)
    ins = ('''\tikuai,q3000)
\t\tucidef_set_led_default "green" "GREEN" "q3000:green" "1"
\t\tucidef_set_led_default "blue" "BLUE" "q3000:blue" "0"
\t\tucidef_set_led_default "red" "RED" "q3000:red" "0"
\t\t;;
''')
    s = s.replace(a, a + ins)
    save(p, s)
    print('01_leds: 已加入 ikuai,q3000 状态灯规则')
else:
    print('01_leds: ikuai,q3000 已存在，跳过')

print('iKuai Q3000/Q6000 注入完成（filogic.mk / platform.sh / 02_network / 01_leds）')
PYEOF
