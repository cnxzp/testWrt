#!/bin/bash
# diy-part1: 在 feeds update 之前执行, 主要加第三方源
# 工作流调用位置: openwrt/ 目录下

# 1. 彻底清除前人在 feeds.conf.default 中遗留的冲突残留行（防止再次报第 11 或 13 行错误）
sed -i '/luci-app-temp-status/d' feeds.conf.default
sed -i '/temp-status/d' feeds.conf.default

# 2. 正常添加符合 Feeds 规范的 kenzok8 dae/daed 源
if ! grep -q "openwrt-daede" feeds.conf.default; then
  echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git' >> feeds.conf.default
fi

# 3. 针对“单体插件仓库”temp-status，不采用 feeds 源机制，直接 git clone 丢进本地 package 目录
# 这样能完全避开 feeds.conf.default 的语法解析，且百分之百能被编译识别
mkdir -p package/custom
git clone --depth 1 https://github.com/OneNAS-space/luci-app-temp-status package/custom/luci-app-temp-status

# 4. 打印 feeds.conf.default 结构，确保控制台日志干净无污染
echo "===== 修复后的 feeds.conf.default 内容 ====="
cat feeds.conf.default
