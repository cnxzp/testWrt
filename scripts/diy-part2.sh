#!/bin/bash
# diy-part2: 在 feeds install 之后、copy .config 之前执行
# 工作流调用位置: openwrt/ 目录下
# 主要做: 主机名、IP、版本标识等轻量定制, 不动内核

# 1. 默认 LAN IP 改成 192.168.1.3
sed -i 's/192\.168\.1\.1/192.168.1.3/g' package/base-files/files/bin/config_generate
if ! grep -q '192\.168\.1\.3' package/base-files/files/bin/config_generate; then
  echo "ERROR: LAN 默认 IP 192.168.1.3 未生效" >&2; exit 1
fi
# =====================================================================
# 【新增功能】强制修改 2.4G 和 5G 的默认无线加密方式为 WPA2-PSK 且密码为 mqy-4708
# =====================================================================

# 准确定位 MTK filogic 架构对应的无线脚本文件
WIFI_CONFIG="package/kernel/mac80211/files/lib/wifi/mac80211.sh"

if [ -f "$WIFI_CONFIG" ]; then
    # 【全新加入】将默认的无线名称（通常原生为 OpenWrt）全局强制替换为 DT
    sed -i 's/ssid=FanchmWrt/ssid=DT/g' $WIFI_CONFIG
    
    # 将默认加密方式从 none 或者是 mixed-psk 统一修改为 wpa2-psk
    sed -i 's/encryption=none/encryption=psk2/g' $WIFI_CONFIG
    sed -i 's/encryption=mixed-psk/encryption=psk2/g' $WIFI_CONFIG
    
    # 强制将默认无线密码行（key）替换或注入为 mqy-4708
    sed -i 's/key=./key=mqy-4708/g' $WIFI_CONFIG
    
    # 防御性规避：如果原生脚本缺乏初始化行，直接整段强制覆盖/追加注入
    sed -i '/set wireless.default_radio${devidx}.ssid/a \\t\t\t\tset wireless.default_radio${devidx}.ssid=DT\n\t\t\t\tset wireless.default_radio${devidx}.encryption=psk2\n\t\t\t\tset wireless.default_radio${devidx}.key=mqy-4708' $WIFI_CONFIG
    
    echo "Wireless SSID successfully set to 'DT' and password set to 'mqy-4708' for both 2.4G and 5G!"
fi

# 2. 默认主机名 -> NatserverWrt (顶栏侧边品牌等取 hostname)
sed -i "s/hostname='[^']*'/hostname='NatserverWrt'/g" package/base-files/files/bin/config_generate
if ! grep -q "hostname='NatserverWrt'" package/base-files/files/bin/config_generate; then
  echo "ERROR: hostname NatserverWrt 未生效" >&2; exit 1
fi

# 3. 固件名 -> NatserverWrt (CONFIG_VERSION_DIST 符号不存在, 改 version.mk 的兜底值;
#    影响镜像文件名前缀 + DISTRIB_ID + openwrt_release 的 %D 显示)
sed -i 's/\$(VERSION_DIST),OpenWrt)/$(VERSION_DIST),NatserverWrt)/' include/version.mk
if ! grep -q '$(VERSION_DIST),NatserverWrt)' include/version.mk; then
  echo "ERROR: VERSION_DIST NatserverWrt 未生效" >&2; exit 1
fi

# 4. 固件版本描述 (LuCI 概览/登录窗口的 Firmware Version)
if [ -f package/base-files/files/etc/openwrt_release ]; then
  echo "DISTRIB_DESCRIPTION='NatserverWrt snapshot + daed (Tenda BE12 Pro)'" >> package/base-files/files/etc/openwrt_release
fi

# 5. 确保 golang 版本足够新 (dae 需要 go 1.21+), feeds 自带一般够, 这里只打印确认
./scripts/feeds list | grep -E "^(dae|daed|luci-app-daede|vmlinux-btf|v2ray-geo)" || echo "WARN: dae 相关 feed 未列出, 请检查 diy-part1 是否生效"


# 6. 浏览器标签页标题 + 登录窗口大标题 (fanchmwrt 主题硬编码 FanchmWrt, 与 hostname 无关)
sed -i 's|<title>FanchmWrt</title>|<title>NatserverWrt</title>|' package/fcm/luci-theme-fanchmwrt/ucode/template/themes/fanchmwrt/header.ut
if ! grep -q '<title>NatserverWrt</title>' package/fcm/luci-theme-fanchmwrt/ucode/template/themes/fanchmwrt/header.ut; then
  echo "ERROR: 浏览器标签 <title>NatserverWrt</title> 未生效 (header.ut 结构变了?)" >&2; exit 1
fi
sed -i "s/'FanchmWrt'/'NatserverWrt'/" package/fcm/luci-theme-fanchmwrt/htdocs/luci-static/resources/view/fanchmwrt/sysauth.js
if ! grep -q "'NatserverWrt'" package/fcm/luci-theme-fanchmwrt/htdocs/luci-static/resources/view/fanchmwrt/sysauth.js; then
  echo "ERROR: 登录窗口标题 NatserverWrt 未生效 (sysauth.js 结构变了?)" >&2; exit 1
fi
if grep -q "'FanchmWrt'" package/fcm/luci-theme-fanchmwrt/htdocs/luci-static/resources/view/fanchmwrt/sysauth.js; then
  echo "ERROR: sysauth.js 仍残留 'FanchmWrt'" >&2; exit 1
fi
echo "OK: 标签页/登录窗口标题 -> NatserverWrt"

echo "diy-part2 done"
