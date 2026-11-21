#!/bin/bash
# 主题换 vantage + 去 argon + iStore + 中文包（在源码根目录执行）
set -e
cd "${1:-.}"

echo "== 1/5 移除 argon =="
rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config \
       package/luci-theme-argon package/luci-app-argon-config

echo "== 2/5 引入 luci-theme-vantage =="
if [ ! -d package/luci-theme-vantage ]; then
  git clone --depth 1 https://github.com/anothaDev/luci-theme-vantage package/luci-theme-vantage
fi

echo "== 3/5 引入 iStore feed =="
grep -q '^src-git istore ' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore.git' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a -p istore || true
./scripts/feeds install -a

echo "== 4/5 默认主题替换 =="
for f in feeds/luci/collections/luci/Makefile feeds/luci/collections/luci-light/Makefile; do
  [ -f "$f" ] && sed -i 's/luci-theme-argon/luci-theme-vantage/g; s/luci-theme-bootstrap/luci-theme-vantage/g' "$f" || true
done
# 打开 luci-i18n-*-zh-cn 生成（部分树把该 foreach 注释掉了）
if [ -f feeds/luci/luci.mk ]; then
  sed -i 's/^# \$(foreach lang,\$(LUCI_LANGUAGES)/$(foreach lang,$(LUCI_LANGUAGES)/' feeds/luci/luci.mk || true
fi

echo "== 5/5 写入配置与默认主题 =="
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci=y
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
# 2026-11-21 RG-EW6000GX Pro 首次构建即因此失败（step「校验机型与主题并 defconfig」报 iStore 未生效）。
CONFIG_PACKAGE_xz-utils=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_taskd=y
CONFIG_PACKAGE_luci-lua-runtime=y
EOF
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-default-theme <<'EOF'
#!/bin/sh
# 首启默认值：主题 vantage、界面语言简体中文、iStore 依赖的 taskd 自启
uci -q batch <<-EOT
	set luci.main.mediaurlbase='/luci-static/vantage'
	set luci.main.lang='zh_cn'
	commit luci
EOT
[ -x /etc/init.d/taskd ] && { /etc/init.d/taskd enable; /etc/init.d/taskd start; }
exit 0
EOF
chmod +x files/etc/uci-defaults/99-default-theme
echo "[done] customize"
