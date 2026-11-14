#!/bin/bash
# CMCC RAX3000M / XR30（NAND 硬改 256M Flash）机型注入
#
# 方案移植自 ReddotCleaner/rax3000m-256m-cloud-build（ImmortalWrt/OpenWrt 25.12 同款）：
#   · 只把 ubi 分区从 114MB(0x7200000) 扩到 250.5MB(0xFA80000)，其余完全沿用上游
#     25.12 的 cmcc_rax3000m 启动方式：KERNEL_IN_UBI + FIT(kernel+rootfs) + /dev/fit0，
#     不编译、不替换 preloader / fip / U-Boot（用 1715173329 那版 256M U-Boot）。
#   · RAX3000M 与 XR30 硬件同源（MT7981B + MT7531，3 LAN + 1 WAN，SPI-NAND 128M 原厂），
#     分区表、MAC 偏移(factory 0x24/0x2a)、WiFi eeprom(factory 0x0) 完全一致，
#     所以 XR30 直接复用 rax3000m 的 base dts + overlay，只改 model 字样。
#
# 设备名用 cmcc_rax3000m_nand / cmcc_xr30_nand，产物文件名好认；
# 但 overlay 里的 compatible 保持 "cmcc,rax3000m"，这样 board_name 仍是 cmcc,rax3000m，
# 02_network / platform.sh 里已有的机型分支不用动（SUPPORTED_DEVICES 同步声明）。
set -e

python3 - <<'PYEOF'
import io, shutil

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

DTS = 'target/linux/mediatek/dts'
OLD = 'reg = <0x580000 0x7200000>;'   # 原厂 128M：ubi 114MB
NEW = 'reg = <0x580000 0xFA80000>;'   # 硬改 256M：0x10000000 - 0x580000 = 250.5MB

# ---------------------------------------------------------------------------
# 1) rax3000m-nand overlay：ubi 分区扩到 250.5MB
# ---------------------------------------------------------------------------
rax_ovl = '%s/mt7981b-cmcc-rax3000m-nand.dtso' % DTS
s = load(rax_ovl)
if NEW not in s:
    assert s.count(OLD) == 1, 'rax3000m ubi 分区锚点异常: %d（上游已改格式，需人工核对）' % s.count(OLD)
    s = s.replace(OLD, NEW)
    save(rax_ovl, s)
assert NEW in load(rax_ovl), 'rax3000m ubi 分区替换失败'
print('✔ rax3000m: ubi 分区已扩为 250.5MB')

# ---------------------------------------------------------------------------
# 2) XR30 base dts：复制 rax3000m 的 base dts，只改 model（compatible 保持一致）
# ---------------------------------------------------------------------------
base = '%s/mt7981b-cmcc-rax3000m.dts' % DTS
xr_base = '%s/mt7981b-cmcc-xr30.dts' % DTS
sb = load(base)
sx = sb.replace('model = "CMCC RAX3000M";', 'model = "CMCC XR30";')
assert sx != sb, 'XR30 base dts 的 model 锚点未命中'
save(xr_base, sx)
print('✔ XR30: base dts 已生成（%s）' % xr_base)

# ---------------------------------------------------------------------------
# 3) XR30 overlay：分区/MAC/WiFi eeprom 与 rax3000m 完全一致，直接复用（含已扩大的 ubi）
# ---------------------------------------------------------------------------
xr_ovl = '%s/mt7981b-cmcc-xr30-nand.dtso' % DTS
shutil.copyfile(rax_ovl, xr_ovl)
assert NEW in load(xr_ovl), 'XR30 overlay 里的 ubi 分区不是 250.5MB'
print('✔ XR30: overlay 已生成（%s）' % xr_ovl)

# ---------------------------------------------------------------------------
# 4) filogic.mk：追加两台 256M 机型（结构完全对齐上游 cmcc_rax3000m，只是只带 nand overlay）
# ---------------------------------------------------------------------------
p = 'target/linux/mediatek/image/filogic.mk'
mk = load(p)

TPL = '''
define Device/%(dev)s
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := %(model)s
  DEVICE_VARIANT := (NAND 256M)
  DEVICE_DTS := %(dts)s
  DEVICE_DTS_OVERLAY := %(ovl)s
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_DTS_LOADADDR := 0x43f00000
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
  IMAGE/sysupgrade.itb := append-kernel | \\
\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | \\
\tpad-rootfs | append-metadata
  SUPPORTED_DEVICES += cmcc,rax3000m
endef
TARGET_DEVICES += %(dev)s
'''

devices = [
    dict(dev='cmcc_rax3000m_nand', model='RAX3000M',
         dts='mt7981b-cmcc-rax3000m', ovl='mt7981b-cmcc-rax3000m-nand'),
    dict(dev='cmcc_xr30_nand', model='XR30',
         dts='mt7981b-cmcc-xr30', ovl='mt7981b-cmcc-xr30-nand'),
]

for d in devices:
    if 'Device/%s\n' % d['dev'] in mk:
        print('filogic.mk: %s 已存在，跳过' % d['dev'])
        continue
    mk += TPL % d
    print('filogic.mk: 已追加 %s' % d['dev'])

save(p, mk)

# 校验：两台机型都必须真的进了 filogic.mk
final = load(p)
for d in devices:
    assert 'define Device/%s\n' % d['dev'] in final, 'filogic.mk 缺少 %s' % d['dev']
    assert 'DEVICE_DTS_OVERLAY := %s\n' % d['ovl'] in final, '%s 的 overlay 未写入' % d['dev']
print('✔ filogic.mk 校验通过')
PYEOF

# ---------------------------------------------------------------------------
# 5) WiFi 双保险：mt76 驱动 + 固件在 filogic target 里是 DEFAULT_PACKAGES，
#    这里再确认一次设备块里的 DEVICE_PACKAGES 没被上游改动剥掉
# ---------------------------------------------------------------------------
grep -q 'DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware' \
  target/linux/mediatek/image/filogic.mk \
  || { echo "::error::filogic.mk 里没有带 mt76 驱动的 DEVICE_PACKAGES，WiFi 会失效"; exit 1; }

# overlay 里必须给 wifi 节点接上 factory eeprom，否则 mt76 拿不到校准数据、起不来
grep -q 'nvmem-cells = <&eeprom_factory_0>;' target/linux/mediatek/dts/mt7981b-cmcc-xr30-nand.dtso \
  || { echo "::error::XR30 overlay 缺 WiFi eeprom（nvmem-cells），开机没有 WiFi"; exit 1; }

echo "RAX3000M / XR30 256M 注入完成（dts / overlay / filogic.mk）"
