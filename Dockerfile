# 定制版 OpenWrt (Docker, x86_64 / J4105)
# 内置: AdGuardHome(luci) + PassWall(含 Xray 内核) + KMS(vlmcsd)
FROM sulinggg/openwrt:x86_64

ARG http_proxy=""
ARG https_proxy=""

ENV TZ=Asia/Shanghai

EXPOSE 22 53 80 3000 1688

# gh_token: 可选构建密钥, 用于提高 api.github.com 请求配额(匿名请求在共享 runner 上极易触发限流)
# GitHub Actions 由 workflow 传入; 本地构建没有也不影响
RUN --mount=type=secret,id=gh_token \
    set -eux; \
    export http_proxy="$http_proxy" https_proxy="$https_proxy" HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"; \
    \
    GH_HDR=""; \
    if [ -s /run/secrets/gh_token ]; then \
      printf 'Authorization: Bearer %s' "$(cat /run/secrets/gh_token)" > /tmp/gh_hdr; \
      GH_HDR="-H @/tmp/gh_hdr"; \
    fi; \
    \
    dl() { \
      [ -n "${1:-}" ] || { echo "ERROR: 下载地址为空 ($2)"; exit 1; }; \
      echo "==> 下载 $2"; \
      curl -fSL --retry 3 --retry-all-errors $GH_HDR -o "$2" "$1" \
        || { echo "ERROR: 下载失败: $1"; exit 1; }; \
      [ -s "$2" ] || { echo "ERROR: 下载到空文件: $2"; exit 1; }; \
    }; \
    gh_api() { \
      curl -fSL --retry 3 --retry-all-errors $GH_HDR "https://api.github.com/$1" \
        || { echo "ERROR: GitHub API 请求失败: $1 (可能触发限流, 稍后重试)"; exit 1; }; \
    }; \
    \
    command -v opkg >/dev/null || { echo "ERROR: 基础镜像不是 opkg 版本, 请检查 sulinggg/openwrt:x86_64 标签"; exit 1; }; \
    \
    echo "==> 换 opkg 国内源"; \
    sed -i 's|downloads.openwrt.org|mirrors.cloud.tencent.com/openwrt|g' /etc/opkg/distfeeds.conf || true; \
    opkg update || { echo "ERROR: opkg update 失败"; exit 1; }; \
    \
    echo "==> 安装基础工具"; \
    opkg install ca-bundle curl wget-ssl unzip jq zoneinfo-asia || true; \
    opkg install luci-i18n-base-zh-cn || true; \
    \
    echo "==> 安装 KMS (vlmcsd)"; \
    opkg install vlmcsd luci-app-vlmcsd || echo "WARN: vlmcsd 安装失败, 可进容器后手动安装"; \
    /etc/init.d/vlmcsd enable 2>/dev/null || true; \
    \
    echo "==> 安装 PassWall 依赖"; \
    opkg remove dnsmasq 2>/dev/null || true; \
    opkg install dnsmasq-full ip-full chinadns-ng dns2socks microsocks tcping luci-compat || true; \
    \
    echo "==> 下载 PassWall"; \
    OWRT_VER="$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2 | cut -d. -f1,2)"; \
    [ -n "$OWRT_VER" ] || { echo "ERROR: 无法识别 OpenWrt 版本"; exit 1; }; \
    case "$OWRT_VER" in 22.03) PW_PREFIX="22.03-_";; *) PW_PREFIX="23.05-24.10_";; esac; \
    PW_JSON="$(gh_api repos/Openwrt-Passwall/openwrt-passwall/releases/latest)"; \
    PW_APP_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-app-passwall_")) | .browser_download_url' | head -1)"; \
    PW_I18N_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-i18n-passwall-zh-cn_")) | .browser_download_url' | head -1)"; \
    dl "$PW_APP_URL" /tmp/pw-app.ipk; \
    dl "$PW_I18N_URL" /tmp/pw-i18n.ipk; \
    opkg install /tmp/pw-app.ipk /tmp/pw-i18n.ipk \
      || opkg install --force-depends /tmp/pw-app.ipk /tmp/pw-i18n.ipk \
      || { echo "ERROR: PassWall 安装失败"; exit 1; }; \
    \
    echo "==> 下载 Xray 内核"; \
    dl "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" /tmp/xray.zip; \
    unzip -o /tmp/xray.zip -d /usr/bin/ || { echo "ERROR: Xray 解压失败"; exit 1; }; \
    chmod +x /usr/bin/xray; \
    \
    echo "==> 下载 AdGuardHome 插件"; \
    AGH_JSON="$(gh_api repos/akihazhang/luci-app-adguardhome/releases/latest)"; \
    AGH_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-app-adguardhome_")) | .browser_download_url' | head -1)"; \
    AGH_I18N_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-i18n-adguardhome-zh-cn_")) | .browser_download_url' | head -1)"; \
    dl "$AGH_URL" /tmp/agh.ipk; \
    dl "$AGH_I18N_URL" /tmp/agh-i18n.ipk; \
    opkg install /tmp/agh.ipk /tmp/agh-i18n.ipk \
      || opkg install --force-depends /tmp/agh.ipk /tmp/agh-i18n.ipk \
      || { echo "ERROR: AdGuardHome 插件安装失败"; exit 1; }; \
    \
    echo "==> 下载 AdGuardHome 主程序"; \
    mkdir -p /opt/AdGuardHome; \
    dl "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz" /tmp/agh.tgz; \
    tar -xz -C /opt/AdGuardHome --strip-components=1 -f /tmp/agh.tgz \
      || { echo "ERROR: AdGuardHome 解压失败"; exit 1; }; \
    chmod +x /opt/AdGuardHome/AdGuardHome; \
    \
    echo "==> 写入旁路由默认配置"; \
    uci set network.lan.proto='static'; \
    uci set network.lan.ipaddr='192.168.2.2'; \
    uci set network.lan.netmask='255.255.255.0'; \
    uci set network.lan.gateway='192.168.2.1'; \
    uci set network.lan.dns='192.168.2.1'; \
    uci commit network; \
    uci set dhcp.lan.ignore='1'; uci commit dhcp; \
    uci set system.@system[0].hostname='OpenWrt-Docker'; uci commit system; \
    (echo "password"; echo "password") | passwd root; \
    \
    rm -rf /tmp/*.ipk /tmp/*.zip /tmp/*.tgz /tmp/gh_hdr /tmp/opkg-lists 2>/dev/null || true; \
    echo "BUILD OK: AdGuardHome + PassWall + vlmcsd"
