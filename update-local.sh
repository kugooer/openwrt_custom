#!/bin/bash
# 本地更新脚本: 拉取最新 GHCR 镜像, 用本地配置目录重建容器
# 敏感配置只存在本机 /opt/openwrt-config/, 不进 public 仓库
set -e

IMAGE=ghcr.io/kugooer/openwrt_custom:x86_64
CONTAINER=openwrt
CONFIG_DIR=/opt/openwrt-config

# --- 首次使用: 从当前运行的容器导出配置 ---
# mkdir -p $CONFIG_DIR
# docker cp $CONTAINER:/etc/config/passwall $CONFIG_DIR/passwall
# docker cp $CONTAINER:/etc/config/adguardhome $CONFIG_DIR/adguardhome
# docker cp $CONTAINER:/opt/AdGuardHome/AdGuardHome.yaml $CONFIG_DIR/AdGuardHome.yaml

echo "==> 拉取最新镜像"
docker pull "$IMAGE"

echo "==> 停止旧容器"
docker stop "$CONTAINER" 2>/dev/null || true
docker rm "$CONTAINER" 2>/dev/null || true

echo "==> 用本地配置启动新容器"
docker run -d --name "$CONTAINER" --restart always --privileged \
  --network macvlan_net --ip 192.168.2.2 \
  -v "$CONFIG_DIR/passwall:/etc/config/passwall" \
  -v "$CONFIG_DIR/adguardhome:/etc/config/adguardhome" \
  -v "$CONFIG_DIR/AdGuardHome.yaml:/opt/AdGuardHome/AdGuardHome.yaml" \
  "$IMAGE"

echo "完成, 容器已用最新镜像 + 本地配置启动"
