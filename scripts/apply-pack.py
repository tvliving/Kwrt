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
                for key in ("mt7981", "mt7986"):
                    if inc.startswith(key):
                        out.setdefault(key, inc)
    except OSError:
        pass
    return out


def fix_soc_includes(text, soc, dstdir):
    """把 dts 中的 SoC include 换成当前源码树实际使用的名称。"""
    def repl(match):
        inc = match.group(1)
        if os.path.exists(os.path.join(dstdir, inc)):
            return match.group(0)
        for key, real in soc.items():
            if inc.startswith(key) and real and inc != real:
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

    # 1) DTS：已存在则保留源码树自己的版本，SoC dtsi 名称按本树推断
    dstdir = os.path.join(mtk, "dts")
    soc = infer_soc_includes(dstdir)
    installed = kept = 0
    for name in sorted(os.listdir(os.path.join(pack, "dts"))):
        dst = os.path.join(dstdir, name)
        if os.path.exists(dst):
            kept += 1
            continue
        with open(os.path.join(pack, "dts", name), encoding="utf-8") as fh:
            text = fh.read()
        text = fix_soc_includes(text, soc, dstdir)
        with open(dst, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        installed += 1
    print("[ok] DTS 安装 %d 个，保留源码树已有 %d 个，SoC dtsi=%s" % (installed, kept, soc))

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