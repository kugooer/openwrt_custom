# 定制版 OpenWrt (Docker, x86_64 / J4105)
# 内置: AdGuardHome(luci) + PassWall(含 Xray 内核) + KMS(vlmcsd)
FROM sulinggg/openwrt:x86_64

ARG http_proxy=""
ARG https_proxy=""

ENV TZ=Asia/Shanghai

EXPOSE 22 53 80 3000 1688

RUN set -eux; \
    export http_proxy="$http_proxy" https_proxy="$https_proxy" HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"; \
    command -v opkg >/dev/null || { echo "ERROR: 基础镜像不是 opkg 版本, 请检查 sulinggg/openwrt:x86_64 标签"; exit 1; }; \
    \
    # ---------- 0. opkg 换国内镜像源(失败不中断) ---------- \
    sed -i 's|downloads.openwrt.org|mirrors.cloud.tencent.com/openwrt|g' /etc/opkg/distfeeds.conf || true; \
    opkg update || opkg update; \
    \
    # ---------- 1. 基础工具 ---------- \
    opkg install ca-bundle curl wget-ssl unzip jq zoneinfo-asia || true; \
    opkg install luci-i18n-base-zh-cn || true; \
    \
    # ---------- 2. KMS (vlmcsd, 监听 1688/tcp) ---------- \
    opkg install vlmcsd luci-app-vlmcsd || echo "WARN: vlmcsd 安装失败, 可进容器后手动 opkg install vlmcsd"; \
    /etc/init.d/vlmcsd enable 2>/dev/null || true; \
    \
    # ---------- 3. PassWall 依赖 ---------- \
    opkg remove dnsmasq 2>/dev/null || true; \
    opkg install dnsmasq-full ip-full chinadns-ng dns2socks microsocks tcping luci-compat || true; \
    \
    # ---------- 4. PassWall 本体(按镜像的 OpenWrt 版本自动选包) ---------- \
    OWRT_VER="$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2 | cut -d. -f1,2)"; \
    case "$OWRT_VER" in 22.03) PW_PREFIX="22.03-_";; *) PW_PREFIX="23.05-24.10_";; esac; \
    PW_JSON="$(curl -sSL --retry 3 https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest)"; \
    PW_APP_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-app-passwall_")) | .browser_download_url' | head -1)"; \
    PW_I18N_URL="$(echo "$PW_JSON" | jq -r --arg p "$PW_PREFIX" '.assets[] | select(.name | startswith($p + "luci-i18n-passwall-zh-cn_")) | .browser_download_url' | head -1)"; \
    curl -sSL --retry 3 -o /tmp/pw-app.ipk "$PW_APP_URL"; \
    curl -sSL --retry 3 -o /tmp/pw-i18n.ipk "$PW_I18N_URL"; \
    opkg install /tmp/pw-app.ipk /tmp/pw-i18n.ipk || opkg install --force-depends /tmp/pw-app.ipk /tmp/pw-i18n.ipk; \
    \
    # ---------- 5. Xray 内核(供 PassWall 调用) ---------- \
    curl -sSL --retry 3 -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"; \
    unzip -o /tmp/xray.zip -d /usr/bin/; \
    chmod +x /usr/bin/xray; \
    \
    # ---------- 6. AdGuardHome luci 插件 ---------- \
    AGH_JSON="$(curl -sSL --retry 3 https://api.github.com/repos/akihazhang/luci-app-adguardhome/releases/latest)"; \
    AGH_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-app-adguardhome_")) | .browser_download_url' | head -1)"; \
    AGH_I18N_URL="$(echo "$AGH_JSON" | jq -r '.assets[] | select(.name | endswith("_all.ipk") and contains("luci-i18n-adguardhome-zh-cn_")) | .browser_download_url' | head -1)"; \
    curl -sSL --retry 3 -o /tmp/agh.ipk "$AGH_URL"; \
    curl -sSL --retry 3 -o /tmp/agh-i18n.ipk "$AGH_I18N_URL"; \
    opkg install /tmp/agh.ipk /tmp/agh-i18n.ipk || opkg install --force-depends /tmp/agh.ipk /tmp/agh-i18n.ipk; \
    \
    # ---------- 7. AdGuardHome 主程序(预置, 免得首次在 luci 里下载) ---------- \
    mkdir -p /opt/AdGuardHome; \
    curl -sSL --retry 3 "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz" \
      | tar -xz -C /opt/AdGuardHome --strip-components=1; \
    chmod +x /opt/AdGuardHome/AdGuardHome; \
    \
    # ---------- 8. 旁路由默认网络: 静态 IP + 关闭 DHCP ---------- \
    uci set network.lan.proto='static'; \
    uci set network.lan.ipaddr='192.168.1.2'; \
    uci set network.lan.netmask='255.255.255.0'; \
    uci set network.lan.gateway='192.168.1.1'; \
    uci set network.lan.dns='192.168.1.1'; \
    uci commit network; \
    uci set dhcp.lan.ignore='1'; uci commit dhcp; \
    uci set system.@system[0].hostname='OpenWrt-Docker'; uci commit system; \
    \
    # ---------- 9. 默认 root 密码, 收尾 ---------- \
    (echo "password"; echo "password") | passwd root; \
    rm -rf /tmp/*.ipk /tmp/*.zip /tmp/opkg-lists 2>/dev/null || true; \
    echo "BUILD OK: AdGuardHome + PassWall + vlmcsd"
