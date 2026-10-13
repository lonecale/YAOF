# Shortcut-FE v2 (SFE v2) 通用移植指南

本目录包含高通 Shortcut-FE v2（基于 QSDK 14.0，`NHSS.QSDK.14.0.r1-00011-O`）针对通用平台（x86/ARM/MIPS）与标准 Linux 内核（5.15 ~ 6.12）的移植包与相关文档。

不依赖 NSS、PPE 或任何高通专用硬件芯片，完全在 CPU 上通过纯软件快速路径转发，**零内核补丁依赖**。

---

## 1. 目录结构

```text
PATCH/sfe-v2/
├── package/             # OpenWrt 源码包（提供 kmod-shortcut-fe 与 kmod-shortcut-fe-cm）
│   ├── Makefile         # 编译规则，集成防火墙配置与 ucitrack 联动
│   ├── patches/         # 单一兼容补丁（001-openwrt-generic-compat.patch）
│   ├── src/             # 连接管理器、兼容层与桩头文件
│   │   ├── sfe_cm.c     # 控制面（conntrack 同步、时钟嘀嗒续期、规则下发）
│   │   ├── sfe_cm.h
│   │   ├── sfe_compat.h # 通用内核兼容层与模块内联 dev_fast_xmit
│   │   ├── asm/unaligned.h
│   │   └── linux/       # debug_mem_usage.h / if_trustsec.h
│   └── files/           # 运行时服务与工具
│       ├── etc/init.d/shortcut-fe             # 防火墙按需启停脚本
│       ├── usr/bin/sfe_dump                  # 状态与统计导出工具
│       └── usr/share/ucitrack/shortcut-fe.json # LuCI 防火墙热重载配置
└── README.md            # 本文件
```

---

## 2. 补丁与设计精简说明

原版 QSDK SFE 针对高通私有内核及 NSS 硬件设计，移植到通用内核只需解决通用兼容与控制面挂接：

### 单一补丁（`001-openwrt-generic-compat.patch`）
* **Makefile**：
  * 去除 `-Werror`，去除依赖私有内核导出的 `sfe_pppoe_mgr.o`；
  * 添加 `shortcut-fe-cm.o` 一同编译；
  * 编译参数加入 `-include $(src)/sfe_compat.h`。通过预包含头文件与 `-I$(src)`，Linux 6.11+ 的 `asm/unaligned.h` 移除及内核函数签名变更全部在垫片中处理，上游业务代码零修改。
* **双模 Ingress 接收钩子**：
  * 在 `sfe.c` 初始化时动态探测 `athrs_fast_nat_recv`。若内核有相关补丁则挂接函数指针获得极致性能；若为通用内核，则自动回退至 Netfilter `NF_INET_PRE_ROUTING`（优先级 `NF_IP_PRI_FIRST` / `NF_IP6_PRI_FIRST`），做到全平台通用且开箱即用。
* **数据面（sfe_ipv4_*.c / sfe_ipv6_*.c）**：
  * 彻底剔除访问 PPE 硬件虚表（`xmit_dev->offload_ops`）的私有代码，纯软直发。

### 模块内联 `dev_fast_xmit`（免内核补丁直通网卡）
在 `sfe_compat.h` 中直接实现 `dev_fast_xmit`：
* 发包时尝试获取网卡硬件 TX 队列自旋锁，直接调用驱动 `netdev_start_xmit`，绕过 Linux qdisc 队列调度层实现零额外开销线速转发。
* 若 TX 队列繁忙或停止，安全返回 `false`，SFE 会平滑回退至内核标准 `dev_queue_xmit` 发送。

### Conntrack 平滑续期机制
SFE 快速转发绕过了 Netfilter 慢速路径。`sfe_cm.c` 在批量同步回调（`sfe_cm_v2_ipv4_sync_many_callback`）中提取 SFE 回传的时钟增量 `inc_ticks`，在同步规则时累加刷新 `ct->timeout`，彻底避免大流量持续长连接被 Linux conntrack GC 超时误杀。

---

## 3. PPPoE 加速机制与实现

### 数据面
SFE v2 数据面（`sfe_pppoe.c`、`sfe_ipv4_tcp.c` 等）原生支持 PPPoE 解包（Decap）与封包（Encap）：
* **下行方向（Decap）**：WAN 网卡收到 `ETH_P_PPP_SES`（0x8864）报文时，SFE 匹配 session id 后直接剥除 PPPoE/PPP 报头（8 字节），恢复为标准 IP 帧发往 LAN。
* **上行方向（Encap）**：LAN 发往外网的数据帧，SFE 直接压入 PPPoE 头并填入 Session ID，外层填上以太网 MAC，直接调用物理网卡接口发出。绕过了 Linux 内核 PPP 驱动的单线程队列与 channel 互斥锁。

### 控制面（如何识别 PPPoE 接口）
原版 QCA ECM 使用了高通给 PPP 驱动打的私有导出函数 `pppoe_channel_addressing_get`。在标准 Linux 内核中该函数不存在。

本方案在 `sfe_cm.c` 中通过 Linux 5.13+ 内核原生公开的 `dev_fill_forward_path()` 实现：
1. 当连接的入/出设备为 `ARPHRD_PPP`（即 `pppoe-wan`）时，`dst_neigh_lookup` 无 ARP 邻居，走虚拟设备解析分支；
2. 调用 `dev_fill_forward_path(dst->dev, NULL, &stack)`，内核会自动回溯出底层真实物理网卡（如 `eth0`）、Session ID 以及对端 BRAS 服务器的 MAC 地址；
3. 将上述参数下发给 SFE 规则表，打上 `PPPOE_ENCAP` / `PPPOE_DECAP` 标记，建立双向硬件无关的纯软加速流；
4. 若回溯失败（如非常规隧道），连接管理器放弃加速，交由内核慢速路径正常路由，不影响网络通断。

---

## 4. 运行时使用与排查

### 防火墙与 LuCI 集成
* **LuCI 界面**：“网络” -> “防火墙” -> “常规设置” 中，分流模式选择 `Shortcut-FE v2 flow offloading` 并保存应用。
* **按需加载与热重载**：模块取消了开机自动盲载。通过 `ucitrack` 联动，当防火墙配置启用 `shortcut_fe` 时自动 `modprobe` 对应模块，禁用时自动 `rmmod` 卸载。

### 命令行排查
```bash
# 手动控制服务
/etc/init.d/shortcut-fe start
/etc/init.d/shortcut-fe stop

# 查看运行状态与连接统计
/usr/bin/sfe_dump
/usr/bin/sfe_dump ipv4
/usr/bin/sfe_dump ipv6

# 查看模块加载
lsmod | grep shortcut
```
