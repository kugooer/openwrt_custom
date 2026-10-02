# 定制版 OpenWrt (Docker, x86_64 / J4105)
# 基础镜像: OpenWrt 官方 rootfs (24.10.8), 内置: AdGuardHome(luci) + PassWall(含 Xray 内核) + KMS(vlmcsd)
FROM openwrt/rootfs:x86-64-24.10.8

ARG http_proxy=""
ARG https_proxy=""
# opkg 国内镜像源(可选)。Actions 上用官方源即可; 国内本地构建慢时可设为
# mirrors.ustc.edu.cn/openwrt 或 mirrors.tuna.tsinghua.edu.cn/openwrt
ARG opkg_mirror=""

ENV TZ=Asia/Shanghai

EXPOSE 22 53 80 3000 1688

# gh_token: 可选构建密钥, 用于提高 api.github.com 请求配额(匿名请求在共享 runner 上极易触发限流)
# GitHub Actions 由 workflow 传入; 本地构建没有也不影响
RUN --mount=type=secret,id=gh_token <<'SCRIPT'
set -eux
export http_proxy="$http_proxy" https_proxy="$https_proxy" HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"

GH_HDR=""
if [ -s /run/secrets/gh_token ]; then
  printf 'Authorization: Bearer %s' "$(cat /run/secrets/gh_token)" > /tmp/gh_hdr
  GH_HDR="-H @/tmp/gh_hdr"
fi

dl() {
  [ -n "${1:-}" ] || { echo "ERROR: 下载地址为空 ($2)"; exit 1; }
  echo "==> 下载 $2"
  # shellcheck disable=SC2086
  curl -fSL --retry 3 --retry-all-errors $GH_HDR -o "$2" "$1" \
    || { echo "ERROR: 下载失败: $1"; exit 1; }
  [ -s "$2" ] || { echo "ERROR: 下载到空文件: $2"; exit 1; }
}
gh_api() {
  # shellcheck disable=SC2086
  curl -fSL --retry 3 --retry-all-errors $GH_HDR "https://api.github.com/$1" \
    || { echo "ERROR: GitHub API 请求失败: $1 (可能触发限流, 稍后重试)"; exit 1; }
}

command -v opkg >/dev/null || { echo "ERROR: 基础镜像不是 opkg 版本"; exit 1; }

echo "==> 检查 DNS"
# 官方 rootfs 的 /etc/resolv.conf 是指向 /tmp/resolv.conf 的悬空软链接;
# 若构建环境未注入 DNS, opkg/curl 会因解析失败瞬间挂掉
if [ ! -e /etc/resolv.conf ]; then
  echo "WARN: /etc/resolv.conf 悬空, 写入公共 DNS"
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
fi
cat /etc/resolv.conf

echo "==> 更新 opkg 软件源"
# rootfs tarball 里没有 /var/lock, opkg 建不了锁文件会直接 255 退出, 先建好
mkdir -p /var/lock /var/log /var/run /var/opkg-lists
if [ -n "$opkg_mirror" ]; then
  echo "使用镜像源: $opkg_mirror"
  sed -i "s|downloads.openwrt.org|$opkg_mirror|g" /etc/opkg/distfeeds.conf || true
fi
opkg update || { echo "ERROR: opkg update 失败"; exit 1; }

echo "==> 安装基础工具"
opkg install ca-bundle curl wget-ssl unzip jq zoneinfo-asia || true
opkg install luci-i18n-base-zh-cn || true

echo "==> 安装 KMS (vlmcsd)"
opkg install vlmcsd luci-app-vlmcsd || echo "WARN: vlmcsd 安装失败, 可进容器后手动安装"
/etc/init.d/vlmcsd enable 2>/dev/null || true

echo "==> 安装 PassWall 依赖"
opkg remove dnsmasq 2>/dev/null || true
opkg install dnsmasq-full ip-full chinadns-ng dns2socks microsocks tcping luci-compat || true

echo "==> 下载 PassWall"
OWRT_VER="$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2 | cut -d. -f1,2)"
[ -n "$OWRT_VER" ] || { echo "ERROR: 无法识别 OpenWrt 版本"; exit 1; }
case "$OWRT_VER" in 22.03) PW_PREFIX="22.03-_";; *) PW_PREFIX="23.05-24.10_";; esac
PW_JSON="$(gh_api repos/Openwrt-Passwall/openwrt-passwall/releases/latest)"
PW_APP_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-app-passwall_")) | .browser_download_url' | head -1)"
PW_I18N_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-i18n-passwall-zh-cn_")) | .browser_download_url' | head -1)"
dl "$PW_APP_URL" /tmp/pw-app.ipk
dl "$PW_I18N_URL" /tmp/pw-i18n.ipk
opkg install /tmp/pw-app.ipk /tmp/pw-i18n.ipk \
  || opkg install --force-depends /tmp/pw-app.ipk /tmp/pw-i18n.ipk \
  || { echo "ERROR: PassWall 安装失败"; exit 1; }

echo "==> 下载 Xray 内核"
dl "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" /tmp/xray.zip
unzip -o /tmp/xray.zip -d /usr/bin/ || { echo "ERROR: Xray 解压失败"; exit 1; }
chmod +x /usr/bin/xray

echo "==> 下载 AdGuardHome 插件"
AGH_JSON="$(gh_api repos/akihazhang/luci-app-adguardhome/releases/latest)"
AGH_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-app-adguardhome_")) | .browser_download_url' | head -1)"
AGH_I18N_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-i18n-adguardhome-zh-cn_")) | .browser_download_url' | head -1)"
dl "$AGH_URL" /tmp/agh.ipk
dl "$AGH_I18N_URL" /tmp/agh-i18n.ipk
opkg install /tmp/agh.ipk /tmp/agh-i18n.ipk \
  || opkg install --force-depends /tmp/agh.ipk /tmp/agh-i18n.ipk \
  || { echo "ERROR: AdGuardHome 插件安装失败"; exit 1; }

echo "==> 下载 AdGuardHome 主程序"
mkdir -p /opt/AdGuardHome
dl "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz" /tmp/agh.tgz
tar -xz -C /opt/AdGuardHome --strip-components=1 -f /tmp/agh.tgz \
  || { echo "ERROR: AdGuardHome 解压失败"; exit 1; }
chmod +x /opt/AdGuardHome/AdGuardHome

echo "==> 写入旁路由默认配置"
cat > /etc/config/network <<'NETEOF'
config interface 'lan'
	option device 'eth0'
	option proto 'static'
	option ipaddr '192.168.2.2'
	option netmask '255.255.255.0'
	option gateway '192.168.2.1'
	option dns '192.168.2.1'
NETEOF
uci set dhcp.lan.ignore='1'; uci commit dhcp
(echo "password"; echo "password") | passwd root

rm -rf /tmp/*.ipk /tmp/*.zip /tmp/*.tgz /tmp/gh_hdr 2>/dev/null || true
echo "BUILD OK: AdGuardHome + PassWall + vlmcsd"
SCRIPT
