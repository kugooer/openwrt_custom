#!/bin/bash
# 本地更新脚本: 检查 GHCR 有无新镜像, 有才重建, 无则跳过
# 敏感配置只存在本机 /opt/openwrt-config/, 不进 public 仓库
set -e

IMAGE=ghcr.io/kugooer/openwrt_custom:x86_64
CONTAINER=openwrt
CONFIG_DIR=/opt/openwrt-config
LOG=/var/log/openwrt-update.log

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# --- 首次使用: 从当前运行的容器导出配置 ---
# mkdir -p $CONFIG_DIR
# docker cp $CONTAINER:/etc/config/passwall $CONFIG_DIR/passwall
# docker cp $CONTAINER:/etc/config/adguardhome $CONFIG_DIR/adguardhome
# docker cp $CONTAINER:/opt/AdGuardHome/AdGuardHome.yaml $CONFIG_DIR/AdGuardHome.yaml

log "检查镜像更新: $IMAGE"
PULL_OUT=$(docker pull "$IMAGE" 2>&1)
echo "$PULL_OUT" >> "$LOG"

if echo "$PULL_OUT" | grep -q "Image is up to date"; then
  log "已是最新, 跳过重建"
  exit 0
fi

log "发现新镜像, 开始重建容器"
docker stop "$CONTAINER" 2>/dev/null || true
docker rm "$CONTAINER" 2>/dev/null || true

docker run -d --name "$CONTAINER" --restart always --privileged \
  --network macvlan_net --ip 192.168.2.2 \
  -v "$CONFIG_DIR/passwall:/etc/config/passwall" \
  -v "$CONFIG_DIR/adguardhome:/etc/config/adguardhome" \
  -v "$CONFIG_DIR/AdGuardHome.yaml:/opt/AdGuardHome/AdGuardHome.yaml" \
  "$IMAGE"

log "重建完成, 已用最新镜像 + 本地配置启动"
