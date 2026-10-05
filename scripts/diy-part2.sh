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
# 5. 【MTK 原厂闭源驱动专用】多频精准物理隔离脚本
# =====================================================================
mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-default-wifi << 'EOF'
#!/bin/sh

# 遍历所有无线接口进行精准匹配
uci -q show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | while read -r iface; do
    device=$(uci -q get wireless.${iface}.device)
    [ -z "$device" ] && continue

    # 获取该设备在 mt_wifi 中的物理路径特征或频段声明
    # 联发科原厂 SDK 5G 芯片固定挂载在 .1.2 节点，或设备名直接叫 radio2 / wlan1
    is_5g=0
    
    # 判定方法 1: 查看 device 的名称是否含有 5g、radio2、wlan1 
    if echo "$device" | grep -qE "5g|radio2|wlan1"; then
        is_5g=1
    fi
    
    # 判定方法 2: 查看原厂驱动底层的 path 路径特征 (MT7987 的 5G 通常在 1.2 节点)
    path=$(uci -q get wireless.${device}.path)
    if echo "$path" | grep -q "1.2"; then
        is_5g=1
    fi

    # 根据判定结果，执行严格的隔离配置
    if [ "$is_5g" -eq 1 ]; then
        # 5G 频段独享配置
        uci set wireless.${iface}.ssid='DT-5G'
        uci set wireless.${iface}.encryption='sae'
    else
        # 2.4G 频段独享配置
        uci set wireless.${iface}.ssid='DT'
        uci set wireless.${iface}.encryption='psk2'
    fi

    # 密码两频保持一致
    uci set wireless.${iface}.key='mqy-4708'
done

uci commit wireless
exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-default-wifi
echo "MTK driver patch applied: 2.4G and 5G successfully separated."


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
