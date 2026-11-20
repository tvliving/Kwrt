#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 devices-pack/<slug> 注入 OpenWrt 源码树（幂等）。

用法: python3 scripts/apply-pack.py <源码根目录> <slug>
"""
import os
import re
import shutil
import sys


def infer_soc_includes(dstdir):
    """从本树已有 dts 里推断 mt7981 / mt7986 使用的 SoC dtsi 名称。"""
    out = {}
    try:
        for fn in sorted(os.listdir(dstdir)):
            if not fn.endswith(".dts"):
                continue
            path = os.path.join(dstdir, fn)
            try:
                with open(path, encoding="utf-8", errors="ignore") as fh:
                    head = "".join(fh.readlines()[:40])
            except OSError:
                continue
            for inc in re.findall(r'#include\s+"([^"]+\.dtsi)"', head):
                m = re.fullmatch(r'(mt798[16][ab]?)\.dtsi', inc)
                if m:
                    out.setdefault(m.group(1)[:6], inc)
    except OSError:
        pass
    return out


SOC_RE = re.compile(r'^(mt798[16][ab]?)\.dtsi$')


def fix_soc_includes(text, soc, dstdir, pack_names):
    """只改写 SoC 级 include（如 mt7981b.dtsi），包内自带文件与已存在文件不动。"""
    def repl(match):
        inc = match.group(1)
        if inc in pack_names or os.path.exists(os.path.join(dstdir, inc)):
            return match.group(0)
        m = SOC_RE.match(inc)
        if not m:
            return match.group(0)
        real = soc.get(m.group(1)[:6])
        if real and real != inc:
            print("[info] %s -> %s" % (inc, real))
            return '#include "%s"' % real
        return match.group(0)

    return re.sub(r'#include\s+"([^"]+\.dtsi)"', repl, text)


def main():
    if len(sys.argv) < 3:
        print("用法: apply-pack.py <srcdir> <slug>")
        return 1
    root, slug = os.path.abspath(sys.argv[1]), sys.argv[2]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pack = os.path.join(here, "devices-pack", slug)
    if not os.path.isdir(pack):
        print("[ERROR] 找不到设备包 %s" % pack)
        return 1
    mtk = os.path.join(root, "target/linux/mediatek")
    if not os.path.isdir(mtk):
        print("[ERROR] %s 不是 OpenWrt 源码树" % root)
        return 1

    # 1) DTS：先原样铺开包内文件，再只对 SoC 级 include 做名称适配；
    #    源码树已有同名 DTS 时保留本树版本（不覆盖既有机型）
    dstdir = os.path.join(mtk, "dts")
    soc = infer_soc_includes(dstdir)
    pack_dts = sorted(os.listdir(os.path.join(pack, "dts")))
    pack_names = set(pack_dts)
    installed, kept = [], 0
    for name in pack_dts:
        dst = os.path.join(dstdir, name)
        if os.path.exists(dst):
            kept += 1
            continue
        shutil.copyfile(os.path.join(pack, "dts", name), dst)
        installed.append(name)
    for name in installed:
        dst = os.path.join(dstdir, name)
        with open(dst, encoding="utf-8") as fh:
            text = fh.read()
        fixed = fix_soc_includes(text, soc, dstdir, pack_names)
        if fixed != text:
            with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(fixed)
    print("[ok] DTS 安装 %d 个，保留源码树已有 %d 个，SoC dtsi=%s" % (len(installed), kept, soc))

    # 2) filogic.mk 追加设备定义（同名 Device 已存在则跳过）
    mk = os.path.join(mtk, "image/filogic.mk")
    with open(os.path.join(pack, "mk.fragment"), encoding="utf-8") as fh:
        frag = fh.read()
    with open(mk, encoding="utf-8") as fh:
        text = fh.read()

    blocks, cur = [], []
    for line in frag.strip().splitlines():
        if line.startswith("define Device/") and cur:
            blocks.append(cur)
            cur = [line]
        else:
            cur.append(line)
    if cur:
        blocks.append(cur)

    added = []
    with open(mk, "a", encoding="utf-8", newline="\n") as fh:
        for blk in blocks:
            name = blk[0].split("Device/", 1)[1].strip()
            if ("define Device/%s\n" % name) in text or ("define Device/%s " % name) in text:
                print("[skip] 上游已定义 %s" % name)
                continue
            fh.write("\n" + "\n".join(blk).rstrip() + "\n")
            added.append(name)
    print("[ok] filogic.mk 追加 %s" % (added or "无"))

    # 3) files/ 覆盖层（board.d 网口映射、固件等）
    files = os.path.join(pack, "files")
    if os.path.isdir(files):
        for dirpath, _, fnames in os.walk(files):
            rel = os.path.relpath(dirpath, files)
            dst_dir = os.path.join(root, rel) if rel != "." else root
            os.makedirs(dst_dir, exist_ok=True)
            for fn in fnames:
                shutil.copyfile(os.path.join(dirpath, fn), os.path.join(dst_dir, fn))
        print("[ok] 覆盖 files/ 资源")

    print("[done] %s" % slug)
    return 0


if __name__ == "__main__":
    sys.exit(main())