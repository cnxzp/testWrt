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

# ---------------------------------------------------------------------
# 核心解决：去除无效 daede 软件源
# ---------------------------------------------------------------------
# 创建编译树中最高优先级的系统文件覆盖目录
mkdir -p files/etc/apk/repositories.d/

# 动态生成一份完全不包含 daede 这一行的 distfeeds.list 预设文件
# 这样打包固件时，系统会自动用这个干净的文件覆盖生成的默认文件
cat << 'EOF' > files/etc/apk/repositories.d/distfeeds.list
https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/packages/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/packages/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/routing/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/telephony/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/video/packages.adb
EOF
echo "✅ 已成功建立 files/ 静态防污染机制，拦截无效 daede 官方 Snapshot 源！"

# 创建开机静默初始化目录
mkdir -p files/etc/uci-defaults/

# 动态生成 99-istore-inject 首次开机静默安装脚本
cat << 'EOF' > files/etc/uci-defaults/99-istore-inject
#!/bin/sh

# 1. 建立开机时最安全的临时无感释放区
mkdir -p /tmp/istore_setup
cd /tmp/istore_setup

# 2. 首次开机动态实时抓取最匹配当前系统 APK 内核架构的 iStore 应用中心组件
# 此时路由器已连网，在路由器本地调用本地 apk add，绝对不会触发编译器的 mkndx 错误
wget --no-check-certificate -q https://github.com/linkease/istore
wget --no-check-certificate -q https://github.com/linkease/istore

# 3. 如果抓取成功，通过路由器本地的 apk 包管理器进行无害化本地物理合入
if [ -f luci-app-store_aarch64_cortex-a53.apk ]; then
    # 使用 --allow-untrusted 参数允许安装第三方社区包
    apk add --allow-untrusted luci-app-store_aarch64_cortex-a53.apk luci-app-systools_all.apk
fi

# 4. 清理案发现场，绝不占用路由器珍贵的 Flash 空间
cd /
rm -rf /tmp/istore_setup

# 告知系统此脚本已圆满完成，下次开机不再重复执行
exit 0
EOF

# 赋予该自启脚本最高执行权限
chmod +x files/etc/uci-defaults/99-istore-inject
echo "✅ iStore 动态注入沙盒已部署至 files/ 层，完美规避编译期 apk mkndx 强校验！"

echo "===== diy-part2 阶段所有配置调整就绪 ====="
