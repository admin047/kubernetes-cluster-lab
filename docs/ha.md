# HA Architecture: Keepalived + MySQL/PostgreSQL/Redis

该文档为仓库中多组件高可用（HA）方案的详细演练指南，基于 `docs/ha.md`，包含变量说明、示例 inventory、逐步执行命令、故障注入与验证步骤，便于在测试环境中复现并验收。

> 注：所有操作均在测试环境或快照上先演练；生产环境请勿直接执行。Playbook 原始 YAML 在本仓库中已作为参考（scripts/ha 已替换为移动提示）。要将 playbook 拆分为可执行文件可参见下文建议。

---

## 前置条件

- 目标节点均可通过 Ansible SSH 访问（免密或凭据管理）。
- 目标节点为 Debian/Ubuntu（apt），如使用 CentOS/RHEL，请把 apt 模块替换为 yum/dnf 并调整 service 名称与路径。
- 已安装 Ansible（推荐 >=2.9），并在控制节点可执行 helm/kubectl 如需。数据库对应工具（mysql client、pg_basebackup、redis-cli）在控制节点/目标节点可用用于验证。
- 在执行会清理/初始化数据目录的任务（Postgres replica 的 `pg_basebackup`）之前，务必备份主节点数据。

---

## 变量说明（可通过 `--extra-vars` 或 inventory/group_vars 指定）

- vip: 虚拟 IP，例如 `192.168.76.100`。
- iface: 承载 VIP 的网卡，例如 `eth0`。
- auth_pass: keepalived 的 auth 密码（请使用安全密码并通过 Vault 管理）。

MySQL 相关：
- mysql_root_password: MySQL root 密码（用 Ansible Vault 存放）
- mysql_repl_user/mysql_repl_password: 复制账号与密码

Postgres 相关：
- pg_repl_user/pg_repl_password: 复制账号与密码
- pg_data_dir: 数据目录（示例：`/var/lib/postgresql/12/main`，需根据版本调整）

Redis 相关：
- redis_master_name: Sentinel 中监控的 master 名称

---

## 示例 inventory

将示例内容放到 `scripts/hosts` 或 `inventory/hosts`：

```ini
[keepalived]
master1 ansible_host=192.168.76.4
backup1 ansible_host=192.168.76.5

[mysql_master]
mysql1 ansible_host=192.168.76.4

[mysql_replica]
mysql2 ansible_host=192.168.76.6

[postgres_master]
pg1 ansible_host=192.168.76.4

[postgres_replica]
pg2 ansible_host=192.168.76.7

[redis_master]
redis1 ansible_host=192.168.76.4

[redis_replica]
redis2 ansible_host=192.168.76.6

[redis_sentinel]
sentinel1 ansible_host=192.168.76.5
```

请替换 IP 与主机名为实际环境，并对组划分进行调整（keepalived 节点一般与数据库节点之一重合）。

---

## 逐步执行（测试环境）

1. 语法校验：

```bash
ansible-playbook --syntax-check -i scripts/hosts docs/ha.md --skip-tags run
```

> 注：docs/ha.md 为说明文档；若已把 playbook 拆分为 `scripts/ha-*.yml`，则对这些文件执行 `--syntax-check`。

2. 干运行（Check mode）：

```bash
ansible-playbook -i scripts/hosts scripts/ha --extra-vars "vip=192.168.76.100 iface=eth0" --check
```

3. 单模块逐一执行（推荐）

- Keepalived：
  ansible-playbook -i scripts/hosts scripts/ha-keepalived.yml --extra-vars "vip=192.168.76.100 iface=eth0"

- MySQL：
  ansible-playbook -i scripts/hosts scripts/ha-mysql.yml --extra-vars "mysql_root_password=XXX mysql_repl_password=YYY"

- PostgreSQL：
  ansible-playbook -i scripts/hosts scripts/ha-postgres.yml --extra-vars "pg_repl_password=YYY"

- Redis：
  ansible-playbook -i scripts/hosts scripts/ha-redis.yml

逐步安装并验证各组件，避免一次性改变整个环境。

---

## 验证命令（执行后用于确认状态）

Keepalived / VIP：

```bash
# 在任一节点上查看 VIP 是否存在
ip addr show | grep <VIP>

# 或简单 ping VIP
ping -c 3 <VIP>
```

MySQL 验证：

```bash
# 在任一能访问 VIP 的客户端上连接
mysql -h <VIP> -uroot -p
# 查看主从状态（在主节点）
mysql -uroot -p -e "SHOW MASTER STATUS;"
# 在从节点查看 replication status
mysql -uroot -p -e "SHOW SLAVE STATUS\G"
```

Postgres 验证：

```bash
# 在主节点上查看主库状态
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# 在从节点应返回 true
# 检查 WAL 接收情况
sudo -u postgres tail -n 200 /var/log/postgresql/postgresql-*.log
```

Redis & Sentinel 验证：

```bash
# 查询 master
redis-cli -h <VIP> INFO replication
# Sentinel 查看
redis-cli -p 26379 SENTINEL masters
```

---

## 故障注入与演练步骤（示例场景）

场景 A：验证 VIP 漂移（Keepalived 故障）

1. 在当前 MASTER 上停止 keepalived：
   `ssh root@master1 systemctl stop keepalived`
2. 等待 5-10s，检查 VIP 是否漂移到备机：
   `ssh root@backup1 ip addr show | grep <VIP>` 或从外部 ping VIP
3. 恢复 master：
   `ssh root@master1 systemctl start keepalived`
4. 验证数据库连接仍然可用（通过 VIP 访问）

场景 B：MySQL ���挂掉并验证槽位切换

1. 在 MySQL master 上暂停 MySQL：`systemctl stop mysql`
2. 在 replica 上检查是否能提升为主（手动或自动，取决于你的架构）
3. 验证数据的一致性、复制状态和客户端可通过 VIP 继续访问

场景 C：Postgres replica 恢复基线备份验证

1. 在 replica 上执行停止、清理并执行 `pg_basebackup`（playbook 已示例）
2. 启动 replica 并确认 `pg_is_in_recovery()` 返回 true

场景 D：Redis Sentinel 故障转移

1. 杀掉 redis-master：`systemctl stop redis-server`（或 kill）
2. 在 Sentinel 节点运行：`redis-cli -p 26379 SENTINEL get-master-addr-by-name <master-name>`，查看新的 master 是否切换
3. 验证客户端是否通过 VIP 或 Sentinel 提供的新主地址写入成功

每次故障注入后，记录时间点与观察到的漂移/切换延迟，作为 SLA 对比项。

---

## 回滚与恢复要点

- 对于数据库 replica 清理操作，请在主节点上保留数据备份（mysqldump、pg_basebackup 或逻辑备份）。
- 如果意外破坏，请停止自动化流程，手工按数据库恢复流程（从备份恢复数据、重建 replica）进行恢复。
- 对于生产密钥/密码，使用 Ansible Vault 或外部 Secret 管理器（Vault/Kubernetes Secrets）来注入敏感信息，不要把密码写死在 playbook 中。

---

## 后续建议

- 将该单一大 Playbook 拆分为 role，并把敏感变量移动到 `group_vars/` 或使用 Vault。
- 增加更详细的监控/告警（Prometheus Alertmanager 针对 VIP 丢失、DB 复制滞后等）。
- 为演练编写自动化测试脚本（例如利用 `keepalived-ha-test.sh`、db-ha-check.sh），并把结果写入日志以便审计。

---

如果你同意，我可以：
- 将 docs/ha.md 中的“YAML playbook 内容”重构为独立的 `scripts/ha-keepalived.yml`、`scripts/ha-mysql.yml`、`scripts/ha-postgres.yml`、`scripts/ha-redis.yml`（并将敏感变量使用 Vault 占位），或者
- 仅把上面内容追加到 docs/ha.md（已完成），并另外生成一份 `docs/ha-checklist.md` 包含演练清单和预检脚本。

请选择下一步或告诉我是否需要我马上拆分 playbook 并把可执行文件放回 `scripts/`（默认会使用安全占位符而不是明文密码）。
