#!/bin/bash
# [CTCGFW]immortalwrt
# Use it under GPLv3, please.
# --------------------------------------------------------
# Convert translation files zh-cn to zh_Hans
# The script is still in testing, welcome to report bugs.


### 1. 处理 po/zh-cn 与 po/zh_Hans 共存情况 ###

find . -type d -path "*/po/zh-cn" | while read -r old_dir; do
  new_dir="$(dirname "$old_dir")/zh_Hans"

  # zh_Hans 是符号链接
  if [ -L "$new_dir" ]; then
    link_target="$(readlink "$new_dir")"

    # 兼容：
    # zh_Hans -> zh-cn
    # zh_Hans -> ./zh-cn
    if [ "$link_target" = "zh-cn" ] || [ "$link_target" = "./zh-cn" ]; then
      rm -f "$new_dir"
      mv "$old_dir" "$new_dir"
      continue
    fi

    # 其他未知符号链接保持原样
    continue
  fi

  # zh_Hans 已经是真实目录时优先保留
  if [ -d "$new_dir" ]; then
    rm -rf "$old_dir"
  fi
done



po_file="$({ find -type f | grep -E "[a-z0-9]+\.zh\-cn.+po"; } 2>"/dev/null")"
for a in ${po_file}; do
  po_new_file="$(echo -e "$a" | sed "s/zh-cn/zh_Hans/g")"

  # 已存在对应 zh_Hans 文件时优先保留
  if [ -f "$po_new_file" ]; then
    rm -f "$a"
    continue
  fi

  [ -n "$(grep "Language: zh_CN" "$a")" ] && sed -i "s/Language: zh_CN/Language: zh_Hans/g" "$a"
  mv "$a" "${po_new_file}" 2>"/dev/null"
done

po_file2="$({ find -type f | grep "/zh-cn/" | grep "\.po"; } 2>"/dev/null")"
for b in ${po_file2}; do
  [ -n "$(grep "Language: zh_CN" "$b")" ] && sed -i "s/Language: zh_CN/Language: zh_Hans/g" "$b"
  po_new_file2="$(echo -e "$b" | sed "s/zh-cn/zh_Hans/g")"
  mv "$b" "${po_new_file2}" 2>"/dev/null"
done

lmo_file="$({ find -type f | grep -E "[a-z0-9]+\.zh_Hans.+lmo"; } 2>"/dev/null")"
for c in ${lmo_file}; do
  lmo_new_file="$(echo -e "$c" | sed "s/zh_Hans/zh-cn/g")"
  mv "$c" "${lmo_new_file}" 2>"/dev/null"
done

lmo_file2="$({ find -type f | grep "/zh_Hans/" | grep "\.lmo"; } 2>"/dev/null")"
for d in ${lmo_file2}; do
  lmo_new_file2="$(echo -e "$d" | sed "s/zh_Hans/zh-cn/g")"
  mv "$d" "${lmo_new_file2}" 2>"/dev/null"
done

po_dir="$({ find -type d | grep "/zh-cn" | sed "/\.po/d" | sed "/\.lmo/d"; } 2>"/dev/null")"
for e in ${po_dir}; do
  po_new_dir="$(echo -e "$e" | sed "s/zh-cn/zh_Hans/g")"

  # 已存在对应 zh_Hans 目录或链接时不覆盖
  if [ -e "$po_new_dir" ] || [ -L "$po_new_dir" ]; then
    continue
  fi

  mv "$e" "${po_new_dir}" 2>"/dev/null"
done

makefile_file="$({ find -type f | grep Makefile | sed "/Makefile./d"; } 2>"/dev/null")"
for f in ${makefile_file}; do
  [ -n "$(grep "zh-cn" "$f")" ] && sed -i "s/zh-cn/zh_Hans/g" "$f"
  [ -n "$(grep "zh_Hans.lmo" "$f")" ] && sed -i "s/zh_Hans.lmo/zh-cn.lmo/g" "$f"
done

makefile_file="$({ find package -type f | grep Makefile | sed "/Makefile./d"; } 2>"/dev/null")"
for g in ${makefile_file}; do
  [ -n "$(grep "golang-package.mk" "$g")" ] && sed -i "s|\.\./\.\.|$\(TOPDIR\)/feeds/packages|g" "$g"
  [ -n "$(grep "luci.mk" "$g")" ] && sed -i "s|\.\./\.\.|$\(TOPDIR\)/feeds/luci|g" "$g"
done

exit 0
