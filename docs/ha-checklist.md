# HA 快速演练清单 (Keepalived + MySQL/PostgreSQL/Redis)

路径：docs/ha-checklist.md
目的：提供可复制的“最小工作流”检查与操作命令，用于在测试环境中快速演练并验证多组件 HA 方案。

---

1) 前置与安全检查（必做）
- 在测试环境或 VM 快照上执行；生产切勿直接运行。备份所有数据库（mysqldump / pg_basebackup / 文件系统快照）。
- 确保 Ansible 控制节点可无密码 SSH 访问目标主机或通过凭据管理器可用。测试：
  ansible -i scripts/hosts all -m ping
- 检查 Ansible 版本：ansible --version（推荐 >= 2.9）。

2) Inventory 与变量
- 使用示例 inventory：scripts/hosts 或 inventory/hosts（参见 docs/ha.md）
- 将敏感变量（mysql_root_password、mysql_repl_password、pg_repl_password、auth_pass）用 Ansible Vault 或外部 Secret 管理；示例：
  ansible-vault create group_vars/all/vault.yml

3) 语法与干运行（Check / Dry-run）
- 如果你已把 Playbook 拆分为组件文件（推荐），先语法检���：
  ansible-playbook --syntax-check -i scripts/hosts scripts/ha-keepalived.yml
  ansible-playbook --syntax-check -i scripts/hosts scripts/ha-mysql.yml
  ansible-playbook --syntax-check -i scripts/hosts scripts/ha-postgres.yml
  ansible-playbook --syntax-check -i scripts/hosts scripts/ha-redis.yml

- 干运行（Check mode）：
  ansible-playbook -i scripts/hosts scripts/ha-keepalived.yml --extra-vars "vip=192.168.76.100 iface=eth0" --check

- 如果尚未拆分 playbook，请先阅读 docs/ha.md 中的 Playbook 示例并手动拆分或按文档步骤执行手动操作。

4) 建议的执行顺序（逐步验证）
- 先部署 keepalived（VIP）并验证 VIP 正常漂移
- 部署 MySQL 主/从（在主上创建 repl 用户 -> 在从上启动复制）并验证
- 部署 PostgreSQL 主/从（在从上用 pg_basebackup 做 base backup）并验证
- 部署 Redis 与 Sentinel，并验证故障切换

5) 快速验证命令
- VIP（任意节点）：
  ip addr show | grep <VIP>
  ping -c 3 <VIP>

- MySQL：
  mysql -h <VIP> -uroot -p
  mysql -uroot -p -e "SHOW MASTER STATUS;"
  mysql -uroot -p -e "SHOW SLAVE STATUS\G"

- PostgreSQL：
  sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
  tail -n 200 /var/log/postgresql/postgresql-*.log

- Redis/Sentinel：
  redis-cli -h <MASTER_HOST> INFO replication
  redis-cli -p 26379 SENTINEL masters

6) 常见故障注入（用于演练）
- VIP 漂移：在当前 master 上停止 keepalived，再检查备机是否接管 VIP：
  ssh root@master1 systemctl stop keepalived
  ssh root@backup1 ip addr show | grep <VIP>

- MySQL 主停机：
  ssh root@mysql1 systemctl stop mysql
  在 replica 检查是否可提升或手动提升并切换 VIP（视架构而定）

- PostgreSQL replica 演练：
  在 replica 执行 playbook 中的 basebackup 流程（或手动）：stop -> remove data -> pg_basebackup -> start

- Redis 故障切换：
  systemctl stop redis-server (在 master)，查看 Sentinel 是否选举新 master

7) 回滚/恢复要点
- 如果 replication 配置或数据被破坏，停止自动化流程并按数据库文档进行恢复（从备份还原、重建 replication）。
- 对关键密钥与密码使用 Vault，不要把明文写入 playbook。

8) 记录与 SLA 指标
- 在每次故障注入记录时间点，测量 VIP 漂移延迟、数据库切换时间、客户端恢复时间，作为演练报告的一部分。

---

快速提示：docs/ha.md 中保留了完整的 Playbook 示例与详细步骤。此清单为“��执行最小集”——建议你先将 Playbook 拆成单独的组件文件后再进行自动化执行（我可以帮你拆分并替换或生成 role 结构）。
