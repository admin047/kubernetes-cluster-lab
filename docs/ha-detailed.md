# 高可用架构（根据你的 Kubernetes 实验环境定制）

本文档基于仓库中现有的实验环境与 inventory（示例节点 IP：192.168.76.4 / 192.168.76.9 / 192.168.76.19 等），将上文的高可用架构说明和演练步骤调整为与你的 lab 环境一致，便于直接复现。

主要组件：
- Keepalived：VIP 漂移（示例 VIP：192.168.76.100）
- Nginx：作为 Kubernetes API 负载均衡器（上游为 K8s Master 节点）
- MySQL：主从复制（示例主从部署在实验节点）
- PostgreSQL：主从（Streaming Replication）
- Redis：Master + Replica + Sentinel（3 哨兵）

注意（重要）：所有会修改数据或清除数据目录的操作必须在测试/快照环境验证，生产不要直接运行。

---

1. 概览（针对你的 lab）

- Kubernetes Master 节点（示例）：
  - k8s-master-1: 192.168.76.4
  - k8s-master-2: 192.168.76.9
  - k8s-master-3: 192.168.76.19

- VIP（供外部访问 Kubernetes API 的 VIP / LB）：192.168.76.100

- Keepalived 节点（示例）：可部署在 192.168.76.4（MASTER）与 192.168.76.9（BACKUP），或与 Nginx LB 节点一致

- 数据库/缓存（示例分布，可按你需求调整）：
  - MySQL 主：192.168.76.4，MySQL 从：192.168.76.6
  - PostgreSQL 主：192.168.76.4，Replica：192.168.76.7
  - Redis Master：192.168.76.4，Redis Replica：192.168.76.6，Sentinel：192.168.76.5

---

2. Keepalived（VIP 漂移）

2.1 架构说明（lab 映射）

- Master 节点：192.168.76.4
  - VIP: 192.168.76.100
  - 优先级: 101
  - 状态: MASTER

- Backup 节点：192.168.76.9
  - VIP: 无
  - 优先级: 100
  - 状态: BACKUP

健康检查（track_script）建议：
- 检查 Nginx 进程
- 检查 kube-apiserver（如果本机运行）或后端存活

2.2 部署（示例命令）

```bash
# 在两台节点执行（��例使用 yum，若为 Debian/Ubuntu 则改用 apt）
yum install -y keepalived

# 拷贝仓库中的示例配置（请在 configs/keepalived/ 放置你的配置模板）
cp configs/keepalived/keepalived-master.conf /etc/keepalived/keepalived.conf

systemctl enable --now keepalived
```

2.3 Master 配置（示例）

- 文件：configs/keepalived/keepalived-master.conf（示例）

```conf
vrrp_script check_nginx {
    script "/etc/keepalived/check_nginx.sh"
    interval 2
    weight -20
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass 1111
    }

    virtual_ipaddress {
        192.168.76.100/24
    }

    track_script {
        check_nginx
    }
}
```

2.4 验证

```bash
ip addr show | grep 192.168.76.100
systemctl status keepalived
# 故障演练：
systemctl stop keepalived
# 在备机检查 VIP 是否出现
```

---

3. Nginx 负载均衡（Kubernetes API LB）

3.1 上游（lab 映射）
- k8s-master-1: 192.168.76.4:6443
- k8s-master-2: 192.168.76.9:6443
- k8s-master-3: 192.168.76.19:6443

3.2 部署

```bash
# 安装 nginx (CentOS/RHEL)
yum install -y nginx
# 拷贝配置
cp configs/nginx/nginx-lb.conf /etc/nginx/nginx.conf
nginx -t
systemctl enable --now nginx
```

3.3 nginx 配置要点（configs/nginx/nginx-lb.conf）

- upstream 中列出 k8s master IP
- 使用 ssl_certificate 指向正确证书（或在测试中使用自签名）
- health check：可以使用 nginx_upstream_check_module 或 external health check（或通过 keepalived track_script）

示例已保存在 docs/ha.md（与本文件内容一致）

3.4 验证

```bash
nginx -t
systemctl status nginx
curl -k https://192.168.76.100:6443/version
```

---

4. MySQL 主从复制（实验示例）

4.1 架构（lab 映射示例）
- Master: 192.168.76.4
- Replica: 192.168.76.6
- 建议：在 Master 上启用 binlog、GTID（若 MySQL 版本支持）以及半同步插件以提高可用性

4.2 部署（要点）

```bash
# 安装（CentOS）
yum install -y mysql-server

# 拷贝配置模板（仓库 configs/mysql/master.cnf）
cp configs/mysql/master.cnf /etc/my.cnf
systemctl enable --now mysqld

# 在 Master 创建 repl 用户（安全存放密码）
mysql -uroot -p -e "CREATE USER 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%'; FLUSH PRIVILEGES;"

# 获取 master 状态
mysql -uroot -p -e "SHOW MASTER STATUS\G"
```

在 Replica 上：

```sql
CHANGE MASTER TO
  MASTER_HOST='192.168.76.4',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_pass',
  MASTER_AUTO_POSITION=1;
START SLAVE;
```

4.3 配置示例（configs/mysql/master.cnf）

```ini
[mysqld]
server-id = 1
log-bin = mysql-bin
binlog-format = ROW
gtid-mode = ON
enforce-gtid-consistency = ON
```

Replica 类似但 server-id 不同并启用 relay-log/read-only

4.4 验证

```bash
mysql -uroot -p -e "SHOW MASTER STATUS\G"
mysql -uroot -p -e "SHOW SLAVE STATUS\G"
# 测试复制
mysql -uroot -p -e "CREATE DATABASE test; USE test; CREATE TABLE t1 (id INT);"
# 在 Replica 上检查数据库存在
mysql -uroot -p -e "SHOW DATABASES;"
```

---

5. Redis Sentinel（实验示例）

5.1 架构映射
- Redis Master: 192.168.76.4
- Redis Replica: 192.168.76.6
- Sentinel 节点: 192.168.76.5 (及其它哨兵)

5.2 部署（要点）

```bash
# 安装（CentOS）
yum install -y redis
cp configs/redis/redis-master.conf /etc/redis/redis.conf
systemctl enable --now redis
# 启动 sentinel
redis-sentinel /etc/redis/sentinel.conf &
```

5.3 示例配置（configs/redis/redis-master.conf & sentinel.conf）见 docs/ha.md

5.4 验证

```bash
redis-cli -h 192.168.76.4 INFO replication
redis-cli -h 192.168.76.5 -p 26379 SENTINEL masters
# 故障转移模拟
redis-cli -h 192.168.76.4 DEBUG sleep 10
```

---

6. 故障注入与演练（要点）

- Keepalived：停止 keepalived 服务，观察 VIP 漂移
- Nginx：停止 nginx，检查是否外部访问中断
- MySQL：停止 master，观察 slave 是否能接管（手动或借助外部代理/自动化）
- Postgres：停止主库并验证 replica 是否接收 WAL
- Redis：停止 master，观察 sentinel 选举新 master

验证命令在 docs/ha-checklist.md 中提供（快速命令）

---

7. 新增脚本（已生成，放在 scripts/08-ha/）

- scripts/08-ha/06-deploy-postgresql-ha.sh：用于在目标节点上部署 PostgreSQL 主/从（交互式/参数化，执行前会提示并需要确认，避免误删数据）。
- scripts/08-ha/07-verify-data-consistency.sh：用于对比主/从表行数、检查 pg_stat_replication 与 LSN 差异，输出差异报告。

（下文包含脚本说明与运行示例）

---

8. 运行示例（演练顺序）

1. 在测试环境准备 inventory（scripts/hosts）并确保 ansible 可以访问所有节点
2. 部署 Keepalived（在 master 和 backup）并验证 VIP
3. 部署 Nginx，指向 k8s master 上游
4. 部署数据库服务（MySQL / Postgres / Redis）并配置复制
5. 逐项验证并执行故障注入

---

如果你同意，我已将相关脚本与配置模板生成到仓库（scripts/08-ha/ 与 configs/postgresql/），你可以按 docs/ha.md 与 docs/ha-checklist.md 的步骤演练。如需我进一步根据你某台 VM 的真实主机名/IP 自动生成 inventory 与一键演练脚本，我可以继续生成。
