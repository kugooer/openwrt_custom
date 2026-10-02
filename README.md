# 定制 OpenWrt (Docker 版, x86_64 / J4105)

基于 `openwrt/rootfs:x86-64-24.10.8`, 预装:

| 组件 | 说明 |
|---|---|
| AdGuardHome | 去广告 DNS, luci 插件 + 主程序已预置到 `/opt/AdGuardHome` |
| PassWall | 代理分流, Xray 内核已预置到 `/usr/bin/xray` |
| KMS | vlmcsd, 开机自启, 监听 `1688/tcp` |

镜像已按旁路由预设: LAN 静态 IP `192.168.2.2`, 网关 `192.168.2.1`, DHCP 已关闭。

## 文件

- `Dockerfile` - 构建定义
- `build.sh` - 构建脚本
- `run.sh` - 启动脚本(macvlan)

## 方案二: GitHub Actions 云构建(推荐, J4105 上不用装构建环境)

1. 在 GitHub 新建仓库(比如 `openwrt-docker`), 把这四个文件 + `.github/workflows/docker-build.yml` 推上去。
2. 仓库的 Actions 页点 `Run workflow`, 等几分钟构建完成。
3. 构建产物在仓库主页右侧 Packages 里, 地址形如 `ghcr.io/你的用户名/openwrt-docker:x86_64`。
   首次使用去 Package 设置里改成 Public, 之后 J4105 上免登录可拉。
4. J4105 上执行:
   ```bash
   IMAGE=ghcr.io/你的用户名/openwrt-docker:x86_64 ./run.sh
   ```
   注意 ghcr.io 国内直连可能慢, 需要走梯子。

## 方案一: 本地构建

```bash
chmod +x build.sh run.sh

# 1. 构建 (J4105 上执行, 约 5-15 分钟)
./build.sh
# GitHub 访问慢就走代理:
# ./build.sh http://192.168.2.x:7890

# 2. 启动 (先按你的内网改好变量, 用 ip a 确认网口名)
IFACE=enp2s0 SUBNET=192.168.2.0/24 GATEWAY=192.168.2.1 IP=192.168.2.2 ./run.sh
```

## 首次配置

1. 访问 `http://192.168.2.2`, 用户名 `root`, 密码 `password`, **登录后立刻改密码**。
2. 旁路由用法: 需要走旁路由的设备, 把网关手动设为 `192.168.2.2`(DNS 也设为它, 即可享受 AdGuardHome 去广告)。
3. **AdGuardHome**: 服务 → AdGuard Home, 首次打开 `http://192.168.2.2:3000` 按向导完成初始化。
   建议在插件设置里开启 **DNS 重定向(把 53 端口重定向到 AdGuardHome)**, 上游 DNS 填 `127.0.0.1`,
   这样 PassWall 的分流规则继续生效, 二者不打架。
4. **PassWall**: 服务 → PassWall, 添加订阅/节点即可。注意 Docker 容器共用宿主机内核,
   `run.sh` 已把宿主机的 `/lib/modules` 挂载进容器并预加载 nft 模块,
   如 TPROXY 模式报错, 换 TCP REDIRECT 模式试试。
5. **KMS**: 已开机自启。客户端管理员 CMD 执行:
   `slmgr /skms 192.168.2.2` 然后 `slmgr /ato`。

## 常见问题

- **构建时下载慢**: `./build.sh` 后面跟代理地址(`./build.sh http://192.168.2.x:7890`); opkg 慢则 `OPKG_MIRROR=mirrors.ustc.edu.cn/openwrt ./build.sh`。
- **宿主机 ping 不通 192.168.2.2**: macvlan 的固有限制, 宿主机和容器默认互不通,
  用局域网内其他设备访问, 或在宿主机上另建 macvlan 子接口。
- **想换网段**: 改 `Dockerfile` 里 `network.lan.*` 四项和 `run.sh` 的变量, 重新构建启动。
- **升级插件**: 进容器 `docker exec -it openwrt sh`, 用 opkg 或 luci 软件包页面更新;
  大版本升级建议重新 `./build.sh` 构建新镜像。
