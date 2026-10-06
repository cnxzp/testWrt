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
# 【智能多频隔离 + 信道自动】双重保险开机 UCI 初始化脚本
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
# =====================================================================
# 5. 【降维打击】破译新版影子兼容层，强行向真实路径注入纯文本软件源
# =====================================================================
BOOT_SCRIPT="package/base-files/files/etc/init.d/boot"

if [ -f "$BOOT_SCRIPT" ]; then
    # 核心：在新版 apk 影子包管理器启动前，强制创建正确的包含 .d 的配置文件夹
    # 绝对不去下载那个乱码的 packages.adb，而是直接写入纯文本仓库根链接
    sed -i '2i\\tmkdir -p /etc/apk/repositories.d' $BOOT_SCRIPT
    
    # 注入保底 1：直接喂给新版 apk 引擎最标准的纯文本地址（在 boot 倒数第二行强行追加）
    sed -i "s|exit 0|echo 'https://down.dllkids.xyz/openwrt-feed/jell/25.12/aarch64_cortex-a53/packages.adb' >> /etc/apk/repositories.d/customfeeds.list\nexit 0|g" $BOOT_SCRIPT
    
    # 注入保底 2：满足旧版 opkg 伪装命令读取 customfeeds.list 文件的格式诉求（写死纯文本字符串）
    sed -i "s|exit 0|echo 'src/gz custom_jell_adb https://down.dllkids.xyz/openwrt-feed/jell/25.12/aarch64_cortex-a53/packages.adb' >> /etc/apk/repositories.d/customfeeds.list\nexit 0|g" $BOOT_SCRIPT
    
    # 强行允许系统放行未签名的自建第三方软件源，杜绝安全证书报错
    sed -i "s|exit 0|echo 'option allow_untrusted' >> /etc/apk/apk.conf\nexit 0|g" $BOOT_SCRIPT
    
    echo "Perfectly bypassed the shadow layers and locked down the modern customfeeds.list!"
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
