#!/bin/bash
# 主题换 vantage + 去 argon + iStore + 中文包 + 首页仪表盘（在源码根目录执行）
set -e
cd "${1:-.}"

echo "== 1/7 移除 argon =="
rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config \
       package/luci-theme-argon package/luci-app-argon-config

echo "== 2/7 引入 luci-theme-vantage =="
if [ ! -d package/luci-theme-vantage ]; then
  git clone --depth 1 https://github.com/anothaDev/luci-theme-vantage package/luci-theme-vantage
fi

echo "== 3/7 引入 iStore feed =="
grep -q '^src-git istore ' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore.git' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a -p istore || true
./scripts/feeds install -a

echo "== 4/7 默认主题替换 =="
for f in feeds/luci/collections/luci/Makefile feeds/luci/collections/luci-light/Makefile; do
  [ -f "$f" ] && sed -i 's/luci-theme-argon/luci-theme-vantage/g; s/luci-theme-bootstrap/luci-theme-vantage/g' "$f" || true
done
# 打开 luci-i18n-*-zh-cn 生成（部分树把该 foreach 注释掉了）
if [ -f feeds/luci/luci.mk ]; then
  sed -i 's/^# \$(foreach lang,\$(LUCI_LANGUAGES)/$(foreach lang,$(LUCI_LANGUAGES)/' feeds/luci/luci.mk || true
fi

echo "== 5/7 写入配置与默认主题 =="
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
CONFIG_PACKAGE_luci-theme-vantage=y
CONFIG_PACKAGE_luci-theme-bootstrap=n
CONFIG_PACKAGE_luci-theme-argon=n
CONFIG_PACKAGE_luci-app-argon-config=n
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
# iStore 的守卫依赖（缺一个 kconfig 就把 luci-app-store 整条丢掉，.config 里查不到该符号）：
#   depends on !(PACKAGE_TAR_XZ) || PACKAGE_xz-utils
# tar 被 select 进来后 TAR_XZ 默认 =y，所以必须显式选 xz-utils。
CONFIG_PACKAGE_xz-utils=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_taskd=y
CONFIG_PACKAGE_luci-lua-runtime=y
# luci-compat / lua 运行时：iStore 与部分老式 Lua 页面仍然需要
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
EOF

echo "== 5.5/7 追加机型附加包（packages.txt 单点维护） =="
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGLIST="$HERE/devices-pack/ew6000gxpro/packages.txt"
if [ -f "$PKGLIST" ]; then
  n=0
  while IFS= read -r pkg || [ -n "$pkg" ]; do
    pkg="$(printf '%s' "$pkg" | tr -d '\r' | sed 's/[[:space:]]*$//')"
    case "$pkg" in ''|'#'*) continue ;; esac
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
    n=$((n + 1))
  done < "$PKGLIST"
  echo "[info] 附加包 $n 个（$PKGLIST）"
else
  echo "::warning::未找到 $PKGLIST，跳过附加包"
fi
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-default-theme <<'EOF'
#!/bin/sh
# 首启默认值：主题 vantage、界面语言简体中文、iStore 依赖的 taskd 自启
# hostname 也要改：vantage 登录页的大标题直接显示 hostname，不改就是 OpenWrt
uci -q batch <<-EOT
	set luci.main.mediaurlbase='/luci-static/vantage'
	set luci.main.lang='zh_cn'
	commit luci
	set system.@system[0].hostname='Kwrt'
	commit system
EOT
[ -x /etc/init.d/taskd ] && { /etc/init.d/taskd enable; /etc/init.d/taskd start; }
# LuCI 的 web 入口与 rpcd 必须开机自启，否则刷完只有 ssh 能进
for s in uhttpd rpcd; do
	[ -x "/etc/init.d/$s" ] && { "/etc/init.d/$s" enable; "/etc/init.d/$s" restart 2>/dev/null || true; }
done
exit 0
EOF
chmod +x files/etc/uci-defaults/99-default-theme
cat > files/etc/uci-defaults/98-lan-ip <<'EOF'
#!/bin/sh
# 后台管理地址固定 192.168.110.1（board.d 生成的 lan 配置在这里改写，首启生效）
uci -q batch <<-EOT
	set network.lan.ipaddr='192.168.110.1'
	set network.lan.netmask='255.255.255.0'
	commit network
	set dhcp.lan.start='100'
	set dhcp.lan.limit='150'
	set dhcp.lan.leasetime='12h'
	commit dhcp
EOT
exit 0
EOF
chmod +x files/etc/uci-defaults/98-lan-ip

# 首页落地页：强制 LuCI /admin 的 firstchild = 状态-概览。
# kiddin9 feed 的 luci-app-vantage 注册了 admin/status/dashboard（order 1），
# 与 luci-mod-status 的 admin/status/overview（order 1）同权；实际表现是
# 点「首页」落到 vantage 仪表盘而不是「状态-概览」。仅撤 quickstart 不够，
# 这里用更高优先级的 menu.d 覆盖，把 dashboard 排除出 firstchild 候选
# （页面本身仍可从菜单访问，不影响功能）。
mkdir -p files/usr/share/luci/menu.d
cat > files/usr/share/luci/menu.d/zzz-kwrt-homepage.json <<'EOF'
{
  "admin/status/dashboard": {
    "title": "Dashboard",
    "order": 9999,
    "firstchild_ineligible": true
  }
}
EOF

echo "== 6/7 品牌：VERSION_DIST 固定为 Kwrt =="
# VERSION_DIST 定义在 package/base-files/image-config.in 的 `if VERSIONOPT` 里，
# 只有 IMAGEOPT/VERSIONOPT 全开时该符号才可见；否则 make defconfig 会把它删掉，
# /etc/openwrt_release 就退回 DISTRIB_ID="OpenWrt"，LuCI 登录页也跟着显示 OpenWrt。
# 直接改默认值，任何一次 defconfig 之后仍然是 Kwrt。
if [ -f package/base-files/image-config.in ]; then
  sed -i 's/^\(\s*\)default "OpenWrt"$/\1default "Kwrt"/' package/base-files/image-config.in
  if grep -q 'default "Kwrt"' package/base-files/image-config.in; then
    echo "[ok] VERSION_DIST 默认值 = Kwrt"
  else
    echo "::warning::VERSION_DIST 默认值替换失败（登录页可能仍显示 OpenWrt）"
  fi
fi

echo "== 7/7 默认展开左侧导航 =="
# 7.0 首页：不再 vendor kidin9/op-packages 的 quickstart。实机验证它的 home.htm
#     是靠 /admin/quickstart/* 的 XHR 拉数据的独立单页壳子，精简固件里后端起不来，
#     XHR 一失败整页只剩「正在加载首页...」，vantage 的侧边栏（由页面自身渲染）
#     也跟着消失。恢复标准 LuCI：状态-概览 作为登录后首页，菜单/侧边栏正常。
echo "[ok] 使用标准 LuCI 首页（状态-概览），不引入 quickstart"

# 7.2 vantage 左侧是图标栏（rail），默认收起、点「Expand navigation」才展开，
#     状态存在 localStorage 的 vantage.rail。这里把默认值改成展开（pinned）；
#     用户手动收起时写 'unpinned'，仍然用户偏好优先。
VUT=package/luci-theme-vantage/ucode/template/themes/vantage/header.ut
VMJ=package/luci-theme-vantage/htdocs/luci-static/resources/menu-vantage.js
python3 - "$VUT" "$VMJ" <<'PY'
import io
import sys

hut, mjs = sys.argv[1], sys.argv[2]


def patch(path, pairs):
    try:
        s = io.open(path, encoding="utf-8").read()
    except IOError:
        print("::warning::未找到 %s" % path)
        return
    hit = 0
    for a, b in pairs:
        if a in s:
            s = s.replace(a, b)
            hit += 1
    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("[ok] %s 替换 %d 处" % (path, hit))


patch(hut, [
    ("localStorage.getItem('vantage.rail') || ''",
     "localStorage.getItem('vantage.rail') || 'pinned'"),
    ("if (rail === 'pinned') r.setAttribute('data-rail', 'pinned');",
     "if (rail !== 'unpinned') r.setAttribute('data-rail', 'pinned');"),
])
patch(mjs, [
    ("storageSet(RAIL_KEY, pinned ? null : 'pinned');",
     "storageSet(RAIL_KEY, pinned ? 'unpinned' : 'pinned');"),
])
PY

# board.d 覆盖脚本需要可执行位（apply-pack 用 copyfile 复制，不带权限）
chmod 755 files/etc/board.d/* 2>/dev/null || true

# iStore 界面中文化（没有内置 iStore 的机型会自己跳过）
bash "$(dirname "$0")/fix-istore-lang.sh" . || true

echo "[done] customize"
