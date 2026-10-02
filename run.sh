#!/bin/bash
# 启动 OpenWrt 旁路由容器 (macvlan 模式)
# 用法: 按需修改下方变量后执行 ./run.sh
#   IFACE=enp1s0 SUBNET=192.168.2.0/24 GATEWAY=192.168.2.1 IP=192.168.2.2 ./run.sh
set -e

IFACE="${IFACE:-enp2s0}"            # J4105 上接内网的那块网口, 用 `ip a` 确认
SUBNET="${SUBNET:-192.168.2.0/24}"  # 内网网段
GATEWAY="${GATEWAY:-192.168.2.1}"   # 主路由 IP
IP="${IP:-192.168.2.2}"             # 旁路由 IP, 必须和 Dockerfile 里 network.lan.ipaddr 一致
IMAGE="${IMAGE:-my-openwrt:x86_64}"  # 用 GHCR 云构建的镜像时改成 ghcr.io/用户名/仓库名:x86_64

# 宿主机预加载 nftables 模块, 供容器内 PassWall 使用(容器内无法 modprobe)
sudo modprobe nft_tproxy nft_socket nft_nat 2>/dev/null || true

# 创建 macvlan 网络(已存在则跳过)
docker network create -d macvlan \
  --subnet="$SUBNET" --gateway="$GATEWAY" \
  -o parent="$IFACE" macnet 2>/dev/null || true

docker rm -f openwrt 2>/dev/null || true

docker run -d --name openwrt --restart always --privileged \
  --network macnet \
  -v /lib/modules:/lib/modules:ro \
  my-openwrt:x86_64 /sbin/init
  $IMAGE /sbin/init

echo "启动完成, 等待约 30 秒后访问 LuCI: http://$IP"
echo "root / password (登录后请立刻修改密码)"
