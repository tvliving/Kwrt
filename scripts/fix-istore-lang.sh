#!/bin/bash
# 让 iStore 前端界面跟随 LuCI 语言（中文固件默认显示中文）
#
# 背景：iStore 是独立 Vue 前端，界面语言由 luci-app-store 的 store.lua 决定：
#   vue_lang() -> i18n.translate("istore_vue_lang")，查不到就回退 "en"
# 而 iStore 自带的 lmo 只有 zh-cn / zh-tw；LuCI 若用 zh_Hans / zh_cn 等代码，
# translate() 匹配不到这个 msgid，结果中文固件里的 iStore 一直是英文界面。
#
# 这里把回退逻辑改成按 LuCI 界面语言直接映射：zh* -> zh-cn（繁体 -> zh-tw）。
#
# 用法：bash scripts/fix-istore-lang.sh [搜索根目录，默认当前目录]
set -u

ROOT="${1:-.}"
f=$(find "$ROOT" -maxdepth 8 -path '*luci-app-store/luasrc/controller/store.lua' 2>/dev/null | head -1)
if [ -z "$f" ]; then
    echo "[skip] 未找到 luci-app-store/luasrc/controller/store.lua（该机型未内置 iStore）"
    exit 0
fi

python3 - "$f" <<'PY'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

new = '''local function vue_lang()
    local i18n = require("luci.i18n")
    local lang = i18n.translate("istore_vue_lang")
    if lang == "istore_vue_lang" or lang == "" then
        -- iStore 自带的 lmo 只有 zh-cn / zh-tw，LuCI 用 zh_Hans、zh_cn 等
        -- 别名时 translate() 查不到，会回退英文；这里按界面语言直接映射
        local ctx = i18n.context
        local cl = (type(ctx) == "table" and ctx.lang) or ""
        if cl:match("^[Zz][Hh]") then
            lang = cl:match("[Hh]ant") and "zh-tw" or "zh-cn"
        else
            lang = "en"
        end
    end
    return lang
end
'''

if "i18n.context" in src and 'lang = cl:match' in src:
    print("[ok] store.lua 已是中文回退逻辑：%s" % path)
elif "local function vue_lang()" not in src:
    print("[warn] %s 里没有 vue_lang()，iStore 语言未处理" % path)
    sys.exit(0)
else:
    pat = re.compile(r"local function vue_lang\(\)\r?\n.*?\r?\nend\r?\n", re.S)
    out, n = pat.subn(new, src, count=1)
    if n:
        io.open(path, "w", encoding="utf-8", newline="\n").write(out)
        print("[ok] 已修正 store.lua 语言回退：%s" % path)
    else:
        print("[warn] store.lua 结构无法识别，未修改：%s" % path)
PY
