#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
给「闪存 >= 128M」的机型自动注入 iStore（软件中心 + 首页）

用法：
    python3 devices/common/inject-istore-128m.py target/linux/mediatek/image/filogic.mk [...]

判定规则：
  · 有 IMAGE_SIZE 且 >= 128m  → 注入
  · 没有 IMAGE_SIZE（eMMC / UBI 大容量机型）→ 注入
  · IMAGE_SIZE < 128m（NOR 小闪存）        → 跳过（Kwrt 全量 rootfs + iStore 装不下）

注入内容：在设备 define 块末尾加一行 DEVICE_PACKAGES += luci-app-store luci-app-quickstart
（走 DEVICE_PACKAGES 而不是全局 .config，这样只有 ≥128M 的机型会带上商店，
  小闪存机型不会被撑爆 image size）
"""
import re
import sys

PAYLOAD = "luci-app-store luci-app-quickstart"
MIN_KB = 128 * 1024

DEFINE_RE = re.compile(r'^define Device/([A-Za-z0-9_.\-]+)\s*$')
ENDEF_RE = re.compile(r'^endef\s*$')
SIZE_RE = re.compile(r'IMAGE_SIZE\s*:?=\s*(\S+)')


def size_to_kb(v):
    m = re.match(r'\s*(\d+)\s*([kKmMgG])', v or '')
    if not m:
        return None
    return int(m.group(1)) * {'k': 1, 'm': 1024, 'g': 1024 * 1024}[m.group(2).lower()]


def process(path):
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')

    out, i = [], 0
    injected, small, already = [], [], []

    while i < len(lines):
        m = DEFINE_RE.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue

        name = m.group(1)
        block = [lines[i]]
        i += 1
        while i < len(lines) and not ENDEF_RE.match(lines[i]):
            block.append(lines[i])
            i += 1
        endef = lines[i] if i < len(lines) else 'endef'
        i += 1

        body = '\n'.join(block)
        ms = SIZE_RE.search(body)
        kb = size_to_kb(ms.group(1)) if ms else None
        big = (kb is None) or (kb >= MIN_KB)   # 无 IMAGE_SIZE 视为 eMMC/UBI 大容量

        if 'luci-app-store' in body:
            already.append(name)
        elif big:
            block.append('  DEVICE_PACKAGES += ' + PAYLOAD)
            injected.append(name)
        else:
            small.append('%s(%s)' % (name, ms.group(1)))

        out.extend(block)
        out.append(endef)

    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out))

    print('[%s] 注入 %d 台 ≥128M 机型' % (path, len(injected)))
    if already:
        print('  已有 iStore，跳过 %d 台' % len(already))
    if small:
        print('  <128M 跳过: %s' % ' '.join(sorted(small)))
    if not injected and not already:
        print('::error::没有匹配到任何机型，检查 %s 是否存在 define Device/*' % path)
        return False
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    ok = True
    for p in argv[1:]:
        ok = process(p) and ok
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
