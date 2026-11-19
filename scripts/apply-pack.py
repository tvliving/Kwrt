#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 devices-pack/<slug> 注入 OpenWrt 源码树（幂等）。
用法: python3 scripts/apply-pack.py <源码根目录> <slug>
"""
import os, shutil, sys

def main():
    if len(sys.argv) < 3:
        print("用法: apply-pack.py <srcdir> <slug>"); return 1
    root, slug = os.path.abspath(sys.argv[1]), sys.argv[2]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pack = os.path.join(here, "devices-pack", slug)
    if not os.path.isdir(pack):
        print("[ERROR] 找不到设备包 %s" % pack); return 1
    mtk = os.path.join(root, "target/linux/mediatek")
    if not os.path.isdir(mtk):
        print("[ERROR] %s 不是 OpenWrt 源码树" % root); return 1

    # 1) DTS
    dstdir = os.path.join(mtk, "dts")
    n = 0
    for name in sorted(os.listdir(os.path.join(pack, "dts"))):
        shutil.copyfile(os.path.join(pack, "dts", name), os.path.join(dstdir, name)); n += 1
    print("[ok] 安装 DTS %d 个" % n)

    # 2) filogic.mk 追加设备定义（已存在则跳过）
    mk = os.path.join(mtk, "image/filogic.mk")
    frag = open(os.path.join(pack, "mk.fragment"), encoding="utf-8").read()
    marker = frag.strip().splitlines()[0]
    text = open(mk, encoding="utf-8").read()
    if marker in text:
        print("[skip] filogic.mk 已包含 %s" % slug)
    else:
        with open(mk, "a", encoding="utf-8") as f:
            f.write("\n" + frag.strip() + "\n")
        print("[ok] filogic.mk 追加设备定义")

    # 3) files/ 覆盖层（board.d 网口映射、固件等）
    files = os.path.join(pack, "files")
    if os.path.isdir(files):
        for dirpath, _, fnames in os.walk(files):
            rel = os.path.relpath(dirpath, files)
            dst = os.path.join(root, rel) if rel != "." else root
            os.makedirs(dst, exist_ok=True)
            for fn in fnames:
                shutil.copyfile(os.path.join(dirpath, fn), os.path.join(dst, fn))
        print("[ok] 覆盖 files/ 资源")
    print("[done] %s" % slug)
    return 0

if __name__ == "__main__":
    sys.exit(main())
