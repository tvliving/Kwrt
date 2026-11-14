#!/bin/bash
# CMCC RAX3000M / XR30（NAND 硬改 256M Flash）机型注入
#
# 方案对齐 tvliving/lede（用户实测可在原厂/社区老 U-Boot 上开机）：
#   · ubi 分区从 114MB(0x7200000) 扩到 250.5MB(0xFA80000)，其余沿用上游 dts；
#     不编译、不替换 preloader / fip / U-Boot。
#   · 启动/升级格式为经典 NAND UBI 卷方案（不是 25.12 的 FIT external rootfs）：
#     kernel = FIT(kernel+dtb) 放 UBI "kernel" 卷，rootfs = squashfs 静态卷，
#     老老 U-Boot 直接 `ubi read kernel; bootm` 即可引导。
#   · 产物三个格式：
#     *-initramfs-recovery.itb  过渡/救援（U-Boot Web 上传）
#     *-squashfs-factory.bin    append-ubi 全量 UBI（老 U-Boot 直接写 ubi 分区）
#     *-squashfs-sysupgrade.bin sysupgrade-tar（系统内 LuCI/命令行升级）
#   · 25.12 的 base dts 里有 bootargs-override="root=/dev/fit0 rootwait"
#     （FIT external 方案专用），本方案必须去掉，否则 root 挂载失败；
#     去掉后与 lede 的 chosen 节点一致（只有 stdout-path）。
#   · platform.sh 同步改路由：25.12 把 cmcc,rax3000m 放在 fit_do_upgrade /
#     fit_check_image 组里，本方案需改为 nand_do_upgrade / nand_do_platform_check。
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
# 1.5) 生成完整版 NAND dts（不依赖 FIT overlay：老 U-Boot 不会应用 overlay）
#      结构 = 25.12 base dts（去掉 bootargs-override="root=/dev/fit0"，
#      那是 FIT external rootfs 专用，本方案下 root=/dev/fit0 不存在）
#      + overlay 的 flash/pinctrl/MAC/WiFi eeprom 段落（direct &ref 语法合并）
#      + ubi 分区扩到 250.5MB；去掉 chosen.rootdisk / ubi_rootdisk（fit0 专用）
# ---------------------------------------------------------------------------
BOA = '\t\tbootargs-override = "root=/dev/fit0 rootwait";\n'
rax_base = '%s/mt7981b-cmcc-rax3000m.dts' % DTS
base_text = load(rax_base)

FLASH_SECTION = '''

&gmac0 {
\tnvmem-cells = <&macaddr_factory_2a 0>;
\tnvmem-cell-names = "mac-address";
};

&gmac1 {
\tnvmem-cells = <&macaddr_factory_24 0>;
\tnvmem-cell-names = "mac-address";
};

&pio {
\tspi0_flash_pins: spi0-pins {
\t\tmux {
\t\t\tfunction = "spi";
\t\t\tgroups = "spi0", "spi0_wp_hold";
\t\t};

\t\tconf-pu {
\t\t\tpins = "SPI0_CS", "SPI0_HOLD", "SPI0_WP";
\t\t\tdrive-strength = <MTK_DRIVE_8mA>;
\t\t\tbias-disable; /* bias-disable */
\t\t};

\t\tconf-pd {
\t\t\tpins = "SPI0_CLK", "SPI0_MOSI", "SPI0_MISO";
\t\t\tdrive-strength = <MTK_DRIVE_8mA>;
\t\t\tbias-disable; /* bias-disable */
\t\t};
\t};
};

&spi0 {
\t#address-cells = <1>;
\t#size-cells = <0>;
\tpinctrl-names = "default";
\tpinctrl-0 = <&spi0_flash_pins>;
\tstatus = "okay";

\tspi_nand@0 {
\t\tcompatible = "spi-nand";
\t\treg = <0>;

\t\tspi-max-frequency = <52000000>;
\t\tspi-tx-bus-width = <4>;
\t\tspi-rx-bus-width = <4>;

\t\tpartitions {
\t\t\tcompatible = "fixed-partitions";
\t\t\t#address-cells = <1>;
\t\t\t#size-cells = <1>;

\t\t\tpartition@0 {
\t\t\t\tlabel = "bl2";
\t\t\t\treg = <0x00000 0x0100000>;
\t\t\t\tread-only;
\t\t\t};

\t\t\tpartition@100000 {
\t\t\t\tlabel = "u-boot-env";
\t\t\t\treg = <0x100000 0x80000>;
\t\t\t};

\t\t\tpartition@180000 {
\t\t\t\tlabel = "factory";
\t\t\t\treg = <0x180000 0x200000>;
\t\t\t\tread-only;

\t\t\t\tnvmem-layout {
\t\t\t\t\tcompatible = "fixed-layout";
\t\t\t\t\t#address-cells = <1>;
\t\t\t\t\t#size-cells = <1>;

\t\t\t\t\teeprom_factory_0: eeprom@0 {
\t\t\t\t\t\treg = <0x0 0x1000>;
\t\t\t\t\t};

\t\t\t\t\tmacaddr_factory_24: macaddr@24 {
\t\t\t\t\t\tcompatible = "mac-base";
\t\t\t\t\t\treg = <0x24 0x6>;
\t\t\t\t\t\t#nvmem-cell-cells = <1>;
\t\t\t\t\t};

\t\t\t\t\tmacaddr_factory_2a: macaddr@2a {
\t\t\t\t\t\tcompatible = "mac-base";
\t\t\t\t\t\treg = <0x2a 0x6>;
\t\t\t\t\t\t#nvmem-cell-cells = <1>;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};

\t\t\tpartition@380000 {
\t\t\t\tlabel = "fip";
\t\t\t\treg = <0x380000 0x200000>;
\t\t\t\tread-only;
\t\t\t};

\t\t\tpartition@580000 {
\t\t\t\tcompatible = "linux,ubi";
\t\t\t\tlabel = "ubi";
\t\t\t\treg = <0x580000 0xFA80000>;
\t\t\t};
\t\t};
\t};
};

&wifi {
\tnvmem-cells = <&eeprom_factory_0>;
\tnvmem-cell-names = "eeprom";
};
'''

def make_nand_dts(model):
    s = base_text.replace(BOA, '')
    assert BOA not in s, 'bootargs-override 未删除'
    assert 'model = "%s";' % model in s, 'model 锚点未命中: %s' % model
    s = s.replace('model = "%s";' % model, 'model = "%s (NAND 256M)";' % model)
    s = s.replace('/dts-v1/;\n', '/dts-v1/;\n#include <dt-bindings/pinctrl/mt65xx.h>\n', 1)
    s = s.rstrip('\n') + '\n' + FLASH_SECTION
    return s

nand_dts = '%s/mt7981b-cmcc-rax3000m-nand.dts' % DTS
save(nand_dts, make_nand_dts('CMCC RAX3000M'))
assert '0xFA80000' in load(nand_dts) and 'root=/dev/fit0' not in load(nand_dts)
print('✔ rax3000m: 完整版 NAND dts 已生成（ubi 250.5MB，无 overlay 依赖）')

# ---------------------------------------------------------------------------
# 2) XR30 完整版 NAND dts（与 rax3000m 同硬件，只改 model 字样）
# ---------------------------------------------------------------------------
xr_nand = '%s/mt7981b-cmcc-xr30-nand.dts' % DTS
sx = make_nand_dts('CMCC RAX3000M').replace(
    'model = "CMCC RAX3000M (NAND 256M)";', 'model = "CMCC XR30 (NAND 256M)";')
assert 'model = "CMCC XR30 (NAND 256M)";' in sx, 'XR30 model 替换失败'
save(xr_nand, sx)
assert '0xFA80000' in load(xr_nand) and 'root=/dev/fit0' not in load(xr_nand)
print('✔ XR30: 完整版 NAND dts 已生成（%s）' % xr_nand)

# ---------------------------------------------------------------------------
# 3) 顺手维护上游 overlay（dtso）：分区同样扩到 250.5MB，保持源码树一致
#    （本方案不依赖 overlay，此步只为树内文件一致性）
# ---------------------------------------------------------------------------
rax_ovl = '%s/mt7981b-cmcc-rax3000m-nand.dtso' % DTS
assert NEW in load(rax_ovl), 'rax3000m overlay 里的 ubi 分区不是 250.5MB'
xr_ovl = '%s/mt7981b-cmcc-xr30-nand.dtso' % DTS
shutil.copyfile(rax_ovl, xr_ovl)
print('✔ overlay 同步维护（非本方案依赖）')

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
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_DTS_LOADADDR := 0x43f00000
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL_IN_UBI := 1
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 250880k
  IMAGES := sysupgrade.bin factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += cmcc,rax3000m
endef
TARGET_DEVICES += %(dev)s
'''

devices = [
    dict(dev='cmcc_rax3000m_nand', model='RAX3000M',
         dts='mt7981b-cmcc-rax3000m-nand'),
    dict(dev='cmcc_xr30_nand', model='XR30',
         dts='mt7981b-cmcc-xr30-nand'),
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
    assert 'DEVICE_DTS := %s\n' % d['dts'] in final, '%s 的 dts 未写入' % d['dev']
    assert 'IMAGE/sysupgrade.bin := sysupgrade-tar' in final, 'sysupgrade-tar 未写入'
    assert 'IMAGE/factory.bin := append-ubi' in final, 'append-ubi 未写入'
print('✔ filogic.mk 校验通过')

# ---------------------------------------------------------------------------
# 4.5) platform.sh 路由：25.12 把 cmcc,rax3000m 放在 fit_do_upgrade / fit_check_image
#      组里（FIT external rootfs 方案）；本方案是经典 NAND UBI 卷 + tar 升级，
#      必须改到 nand_do_upgrade / nand_do_platform_check 分支
# ---------------------------------------------------------------------------
ps = 'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh'
psrc = load(ps)
BOARD_LINE = '\tcmcc,rax3000m|\\\n'

if psrc.count('\tcmcc,rax3000m)') == 2:
    print('✔ platform.sh: cmcc,rax3000m 路由已就位，跳过')
else:
    def retarget(s, func_name, action_block, new_branch):
        a = s.index(func_name)
        e = s.index(action_block, a)
        seg = s[a:e]
        assert BOARD_LINE in seg, '%s: 未找到 cmcc,rax3000m 分组行' % func_name
        seg = seg.replace(BOARD_LINE, '', 1)
        s = s[:a] + seg + s[e:]
        e2 = s.index(action_block, a) + len(action_block)
        return s[:e2] + new_branch + s[e2:]

    psrc = retarget(psrc, 'platform_do_upgrade() {',
                    '\t\tfit_do_upgrade "$1"\n\t\t;;\n',
                    '\tcmcc,rax3000m)\n\t\tnand_do_upgrade "$1"\n\t\t;;\n')
    psrc = retarget(psrc, 'platform_check_image() {',
                    '\t\tfit_check_image "$1"\n\t\treturn $?\n\t\t;;\n',
                    '\tcmcc,rax3000m)\n\t\tnand_do_platform_check "$board" "$1"\n\t\treturn $?\n\t\t;;\n')

    # platform_copy_config：从 emmc 组摘掉（NAND 升级不需要）
    a = psrc.index('platform_copy_config() {')
    e = psrc.index('mediatek,mt7988a-rfb)', a)
    seg = psrc[a:e]
    if BOARD_LINE in seg:
        psrc = psrc[:a] + seg.replace(BOARD_LINE, '', 1) + psrc[e:]
    save(ps, psrc)
    print('✔ platform.sh: cmcc,rax3000m 已路由到 nand_do_upgrade / nand_do_platform_check')

final = load(ps)
assert final.count('\tcmcc,rax3000m)') == 2, \
    'platform.sh 路由分支数量异常: %d' % final.count('\tcmcc,rax3000m)')
fit_grp = final.split('platform_do_upgrade() {')[1].split('fit_do_upgrade "$1"')[0]
assert 'cmcc,rax3000m|' not in fit_grp, 'fit_do_upgrade 组仍含 cmcc,rax3000m'
chk_grp = final.split('platform_check_image() {')[1].split('fit_check_image "$1"')[0]
assert 'cmcc,rax3000m|' not in chk_grp, 'fit_check_image 组仍含 cmcc,rax3000m'
print('✔ platform.sh: cmcc,rax3000m 已路由到 nand_do_upgrade / nand_do_platform_check')
PYEOF

# ---------------------------------------------------------------------------
# 5) WiFi 双保险：mt76 驱动 + 固件在 filogic target 里是 DEFAULT_PACKAGES，
#    这里再确认一次设备块里的 DEVICE_PACKAGES 没被上游改动剥掉
# ---------------------------------------------------------------------------
grep -q 'DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware' \
  target/linux/mediatek/image/filogic.mk \
  || { echo "::error::filogic.mk 里没有带 mt76 驱动的 DEVICE_PACKAGES，WiFi 会失效"; exit 1; }

# 完整版 dts 里必须给 wifi 节点接上 factory eeprom，否则 mt76 拿不到校准数据、起不来
for f in target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-nand.dts \
         target/linux/mediatek/dts/mt7981b-cmcc-xr30-nand.dts; do
  grep -q 'nvmem-cells = <&eeprom_factory_0>;' "$f" \
    || { echo "::error::$f 缺 WiFi eeprom（nvmem-cells），开机没有 WiFi"; exit 1; }
  grep -q 'reg = <0x580000 0xFA80000>;' "$f" \
    || { echo "::error::$f 的 ubi 分区不是 250.5MB"; exit 1; }
  grep -q 'root=/dev/fit0' "$f" \
    && { echo "::error::$f 仍含 bootargs-override（root=/dev/fit0），老 U-Boot 方案会挂载失败"; exit 1; }
done

echo "RAX3000M / XR30 256M 注入完成（完整版 dts / filogic.mk / platform.sh 路由）"
