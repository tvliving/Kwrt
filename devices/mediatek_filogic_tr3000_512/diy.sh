#!/bin/bash
# Cudy TR3000 512MB 硬改版机型注入（NAND，mod-490 布局，方案移植自 tvliving/cudy-tr3000-512）
# 512MB 版 DTS 由 diy/ 目录直接覆盖；本脚本仅向 filogic.mk 追加设备块。
set -e

python3 - <<'PYEOF'
import io

def load(p):
    return io.open(p, encoding='utf-8', newline='').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

p = 'target/linux/mediatek/image/filogic.mk'
s = load(p)
assert 'cudy_tr3000-512mb-v1' not in s, 'filogic.mk 已包含 cudy_tr3000-512mb-v1'
block = '''
define Device/cudy_tr3000-512mb-v1
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := 512mb v1
  DEVICE_DTS := mt7981b-cudy-tr3000-512mb-v1
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += R47
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 520000k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
'''
save(p, s + block)
print('TR3000-512 注入完成（filogic.mk 设备块）')
PYEOF
