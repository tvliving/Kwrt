#!/bin/bash
#=================================================
# 为「闪存 >= 128M」的机型补齐 iStore 软件中心 + 简体中文语言包
#
# 用法：在 openwrt 源码根目录执行（feeds 已 install、devices/common/patches 已打完）
#         bash devices/common/istore-zh.sh
#
# 背景（两个坑，都是静默失败，产物里看不出来）：
#  1) devices/common/patches/luci_mk.patch 为了省体积，把 luci.mk 里的
#     $(foreach lang,$(LUCI_LANGUAGES),... LuciTranslation ...) 注释掉了
#     → 所有 luci-i18n-*-zh-cn 包不生成：LuCI「语言」菜单里没有简体中文，
#       界面只有英文（表现就是「没有中文包」）；同时 luci-app-quickstart
#       依赖 luci-i18n-ttyd-zh-cn，依赖不满足被 kconfig 静默剔除（iStore 首页丢失）。
#  2) feed 里的 luci-app-store 带 @(x86_64||aarch64) 架构约束，
#     在 defconfig 阶段会被 kconfig 静默丢弃，产物里没有 iStore。
#     改成和 lede 同样「树内 vendor + 去掉架构约束」，并加断言防止再次静默丢失。
#
# 注意：<64M NOR 小闪存机型不要调用本脚本（语言包+商店会撑爆 image size）。
#=================================================
set -e
TOP="$(pwd)"

# ── 1. 启用 luci-i18n-*-zh-cn 语言包生成 ─────────────────────────────
if [ -f feeds/luci/luci.mk ]; then
  if grep -q '^# \$(foreach lang,\$(LUCI_LANGUAGES)' feeds/luci/luci.mk; then
    sed -i 's/^# \$(foreach lang,\$(LUCI_LANGUAGES)/$(foreach lang,$(LUCI_LANGUAGES)/' feeds/luci/luci.mk
  fi
  grep -q '^\$(foreach lang,\$(LUCI_LANGUAGES)' feeds/luci/luci.mk \
    || { echo "::error::feeds/luci/luci.mk 语言包生成未启用"; exit 1; }
  echo "✔ 已启用 luci-i18n-*-zh-cn 语言包生成"
else
  echo "::error::feeds/luci/luci.mk 不存在，feeds 未安装？"
  exit 1
fi

# ── 2. 树内 vendor iStore（软件中心 + 首页）──────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --filter=blob:none --sparse \
  https://github.com/kiddin9/op-packages.git "$tmp/repo"
git -C "$tmp/repo" sparse-checkout set \
  luci-app-store luci-app-quickstart quickstart taskd luci-lib-taskd luci-lib-xterm

for p in luci-app-store luci-app-quickstart quickstart taskd luci-lib-taskd luci-lib-xterm; do
  rm -rf "package/$p"
  cp -a "$tmp/repo/$p" "package/$p"
  [ -f "package/$p/Makefile" ] || { echo "::error::iStore 包缺失: $p"; exit 1; }
done
# 目标均为 aarch64（MT7981/MT7986/MT7988），去掉 x86_64/aarch64 之外一律不许选的约束
sed -i 's#@(x86_64||aarch64) ##' package/luci-app-store/Makefile
echo "✔ iStore 软件中心 + 首页已 vendor 到 package/"

# ── 3. 默认简体中文（不依赖浏览器 Accept-Language）──────────────────
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/zzz-zh-cn <<'UCIDEFAULT'
#!/bin/sh
# 默认使用简体中文界面
uci -q set luci.main.lang='zh-cn'
uci -q set luci.languages.zh_cn='简体中文 (Simplified Chinese)'
uci -q commit luci
exit 0
UCIDEFAULT
chmod +x files/etc/uci-defaults/zzz-zh-cn
echo "✔ 已加入默认中文 uci-defaults：files/etc/uci-defaults/zzz-zh-cn"
