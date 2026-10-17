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
# 添加自定义软件源--- rc.local 守护进程（改用 >> 追加防止抹除）
# =====================================================================
mkdir -p package/base-files/files/etc
cat > package/base-files/files/etc/rc.local << 'EOF'
#!/bin/sh
(
    sleep 5
    mkdir -p /etc/apk/repositories.d
    mkdir -p /etc/opkg
    # 第一行可以用 > 或者是用 >>（如果你想保留原厂自带的注释，这里也必须用 >>）
    # 为了保险，如果你想完全不破坏原厂注释，这里全部统一改为 >> 
    echo 'https://down.dllkids.xyz/openwrt-feed/jell/25.12/aarch64_cortex-a53/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
    echo 'src/gz custom_jell_adb https://down.dllkids.xyz/openwrt-feed/jell/25.12/aarch64_cortex-a53/packages.adb' >> /etc/opkg/customfeeds.list 
    # 核心修正：后续的写入必须全部使用 >> 追加，绝对不能用单大于号 > !
    echo 'https://down.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
    echo 'src/gz custom_dllkids_adb https://down.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb' >> /etc/opkg/customfeeds.list
    # 放行未签名策略
    echo "option allow_untrusted" >> /etc/apk/apk.conf
    echo "option check_signature 0" >> /etc/opkg.conf
) &
exit 0
EOF
chmod +x package/base-files/files/etc/rc.local

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

# 查找源码中所有可能生成该无效源的模板或配置文件，并将其直接抹去
find package/ -type f -name "distfeeds.list" -exec sed -i '/daede/d' {} + 2>/dev/null || true
# 如果源码直接将此文件放在 base-files 目录中
if [ -f package/base-files/files/etc/apk/repositories.d/distfeeds.list ]; then
    sed -i '/downloads.openwrt.org.*daede/d' package/base-files/files/etc/apk/repositories.d/distfeeds.list
fi

# =====================================================================
# 终极修复：免编译注入 iStore，防止 fanchmwrt 界面变乱和全英文
# =====================================================================
echo "正在为新版架构免编译注入纯净版 iStore..."

# 1. 创建临时下载目录
mkdir -p /tmp/istore_download && cd /tmp/istore_download

# 2. 从 iStore 官方免编译通道下载最新的纯脚本安装包
wget --no-check-certificate -q https://github.com/istoreos/istore

# 3. 解压释放出 iStore 的纯净前端和控制脚本（不含任何会搞乱主界面的魔改 luci-base）
if [ -f istore-reinstall.run ]; then
    chmod +x istore-reinstall.run
    # 借助安装脚本提取出纯净的 luci-app-store 资源
    sh istore-reinstall.run --extract
    
    # 4. 将提取出的干净插件文件，原封不动复制到编译树的目标根文件系统中
    if [ -d ipk ]; then
        # 提取本地系统包并直接映射到 openwrt 的自定义打包目录
        # 注意：工作流此时在 openwrt/ 目录下，我们要把文件丢进当前目录的 files/ 中
        mkdir -p $GITHUB_WORKSPACE/openwrt/files
        tar -zxf ipk/luci-app-store*.tar.gz -C $GITHUB_WORKSPACE/openwrt/files/ 2>/dev/null || true
        echo "✅ iStore 纯净文件成功注入到固件的 files 预留层！"
    fi
fi

# 5. 清理临时下载的缓存
cd $GITHUB_WORKSPACE/openwrt
rm -rf /tmp/istore_download

echo "diy-part2 done"
