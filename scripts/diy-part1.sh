#!/bin/bash
# diy-part1: 在 feeds update 之前执行, 主要加第三方源
# 工作流调用位置: openwrt/ 目录下

# 1. 确保文件末尾有换行符，防止前人留下的内容与我们的新内容挤在同一行
echo "" >> feeds.conf.default

# 2. 添加 kenzok8 的 dae/daed 源
if ! grep -q "openwrt-daede" feeds.conf.default; then
  echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git' >> feeds.conf.default
fi

# 3. 添加 luci-app-temp-status 源（安全追加，带换行）
if ! grep -q "luci-app-temp-status" feeds.conf.default; then
  echo "" >> feeds.conf.default
  echo 'src-git temp-status https://github.com/OneNAS-space/luci-app-temp-status.git' >> feeds.conf.default
fi

# 4. 打印最终文件内容，方便在 GitHub Actions 日志中排查
echo "===== 最终的 feeds.conf.default 内容 ====="
cat feeds.conf.default
