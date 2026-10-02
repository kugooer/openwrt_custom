#!/bin/bash
# 构建定制 OpenWrt 镜像
# 用法:
#   ./build.sh                        # 直接构建
#   ./build.sh http://192.168.2.x:7890  # 走代理构建(GitHub 访问慢时用)
set -e
cd "$(dirname "$0")"
export DOCKER_BUILDKIT=1

PROXY="${1:-}"
ARGS=()
if [ -n "$PROXY" ]; then
  ARGS+=(--build-arg "http_proxy=$PROXY" --build-arg "https_proxy=$PROXY")
  echo "使用代理构建: $PROXY"
fi
# 国内本地构建且 opkg 慢时: OPKG_MIRROR=mirrors.ustc.edu.cn/openwrt ./build.sh
if [ -n "${OPKG_MIRROR:-}" ]; then
  ARGS+=(--build-arg "opkg_mirror=$OPKG_MIRROR")
  echo "使用 opkg 镜像源: $OPKG_MIRROR"
fi

docker build "${ARGS[@]}" -t my-openwrt:x86_64 .
echo "构建完成: my-openwrt:x86_64"
docker images my-openwrt:x86_64
