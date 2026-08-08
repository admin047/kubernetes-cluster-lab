# HA Architecture: Keepalived + MySQL/PostgreSQL/Redis

该文件为仓库中 scripts/ha 的文档化移位版（已从 scripts/ 目录移除，保存在 docs/ha.md），用于保存详细的 Playbook 内容与说明，便于阅读而不放在 scripts 运行目录中。

说明：
- 原始 playbook 为 Ansible YAML 格式，包含 Keepalived、MySQL 主从、PostgreSQL 主从 与 Redis（含 Sentinel）配置示例。
- 为避免把过于详细的文档和配置混入运行脚本目录（scripts/），我已将原始内容迁移到本文档。

Playbook 内容（YAML）：

```yaml
---
# 多组件高可用方案：Keepalived + MySQL/PostgreSQL/Redis
# 文件名：scripts/ha
# 说明：此 Playbook 假设你在 inventory 中将节点分组为：
#  - keepalived : 负责 VIP 漂移的节点（通常与数据库节点相同）
#  - mysql_master / mysql_replica
#  - postgres_master / postgres_replica
#  - redis_master / redis_replica
#
# 使用方式（示例）：
# ansible-playbook -i scripts/hosts scripts/ha --extra-vars "vip=192.168.76.100 iface=eth0"
#
# 注意：本 playbook 以 Debian/Ubuntu 系统为例，生产环境请先在测试环境验证。

- name: Install and configure Keepalived on HA nodes
  hosts: keepalived
  become: yes
  vars:
    vip: "{{ vip | default('192.168.76.100') }}"
    iface: "{{ iface | default('eth0') }}"
    state_master_hint: "{{ (inventory_hostname == groups['keepalived'][0]) | ternary('MASTER','BACKUP') }}"
    priority_base: "{{ (groups['keepalived'].index(inventory_hostname) | int) | default(100) }}"
    vrrp_router_id: 51
    auth_pass: "securepass"
  tasks:
    - name: Install keepalived
      apt:
        name: keepalived
        state: present
        update_cache: yes

    - name: Ensure keepalived service enabled
      systemd:
        name: keepalived
        enabled: yes
        state: started

    - name: Create keepalived configuration
      copy:
        dest: /etc/keepalived/keepalived.conf
        owner: root
        group: root
        mode: '0644'
        content: |
          vrrp_instance VI_1 {
              state {{ state_master_hint }}
              interface {{ iface }}
              virtual_router_id {{ vrrp_router_id }}
              priority {{ (priority_base | int) + 100 }}
              advert_int 1
              authentication {
                  auth_type PASS
                  auth_pass {{ auth_pass }}
              }
              virtual_ipaddress {
                  {{ vip }}
              }
          }
      notify: Restart keepalived

  handlers:
    - name: Restart keepalived
      systemd:
        name: keepalived
        state: restarted

- name: MySQL primary/replica setup
  hosts: mysql_master:mysql_replica
  become: yes
  vars:
    mysql_root_password: "rootpasswd"
    mysql_repl_user: repl
    mysql_repl_password: replpasswd
    mysql_server_id_master: 100
    mysql_server_id_replica_base: 200
    mysql_bind_address: '0.0.0.0'
  tasks:
    - name: Install MySQL server
      apt:
        name: mysql-server
        state: present
        update_cache: yes

    - name: Ensure MySQL is running
      systemd:
        name: mysql
        enabled: yes
        state: started

    - name: Configure MySQL replication settings (master/replica)
      block:
        - name: Create replication my.cnf snippet
          copy:
            dest: /etc/mysql/conf.d/replication.cnf
            owner: root
            group: root
            mode: '0644'
            content: |
              [mysqld]
              bind-address = {{ mysql_bind_address }}
              server-id = {{ (inventory_hostname in groups['mysql_master']) | ternary(mysql_server_id_master, (mysql_server_id_replica_base + groups['mysql_replica'].index(inventory_hostname) | int)) }}
              log_bin = /var/log/mysql/mysql-bin.log
              binlog_format = ROW
              expire_logs_days = 7
              max_connections = 200
      notify: Restart mysql

    - name: Ensure replication user exists on master
      when: inventory_hostname in groups['mysql_master']
      mysql_user:
        login_user: root
        login_password: "{{ mysql_root_password }}"
        name: "{{ mysql_repl_user }}"
        password: "{{ mysql_repl_password }}"
        priv: "*.*:REPLICATION SLAVE"
        host: "%"
        state: present

    - name: Get master status for replication
      when: inventory_hostname in groups['mysql_master']
      mysql_replication:
        mode: status
      register: master_status

    - name: Configure replica to replicate from master
      when: inventory_hostname in groups['mysql_replica']
      mysql_replication:
        mode: changemaster
        master_host: "{{ groups['mysql_master'][0] }}"
        master_user: "{{ mysql_repl_user }}"
        master_password: "{{ mysql_repl_password }}"
        master_log_file: "{{ hostvars[groups['mysql_master'][0]]['master_status']['File'] | default('') }}"
        master_log_pos: "{{ hostvars[groups['mysql_master'][0]]['master_status']['Position'] | default('') }}"

  handlers:
    - name: Restart mysql
      systemd:
        name: mysql
        state: restarted

- name: PostgreSQL primary/replica setup
  hosts: postgres_master:postgres_replica
  become: yes
  vars:
    pg_repl_user: pg_repl
    pg_repl_password: pg_repl_pass
    pg_data_dir: /var/lib/postgresql/12/main
    pg_wal_level: replica
    pg_max_wal_senders: 5
  tasks:
    - name: Install postgresql
      apt:
        name: postgresql
        state: present
        update_cache: yes

    - name: Ensure postgresql running
      systemd:
        name: postgresql
        enabled: yes
        state: started

    - name: Configure postgresql.conf for streaming replication
      copy:
        dest: /etc/postgresql/12/main/postgresql.conf.d/ha.conf
        owner: postgres
        group: postgres
        mode: '0644'
        content: |
          wal_level = '{{ pg_wal_level }}'
          max_wal_senders = {{ pg_max_wal_senders }}
          wal_keep_segments = 32
      notify: Restart postgresql

    - name: Ensure replication user exists on master
      when: inventory_hostname in groups['postgres_master']
      become_user: postgres
      postgresql_user:
        name: "{{ pg_repl_user }}"
        password: "{{ pg_repl_password }}"
        role_attr_flags: REPLICATION
        state: present

    - name: Create base backup on replica and configure recovery
      when: inventory_hostname in groups['postgres_replica']
      block:
        - name: Stop postgresql on replica
          systemd:
            name: postgresql
            state: stopped
            enabled: true

        - name: Clean data dir
          file:
            path: "{{ pg_data_dir }}"
            state: absent

        - name: Create empty data dir
          file:
            path: "{{ pg_data_dir }}"
            state: directory
            owner: postgres
            group: postgres
            mode: '0700'

        - name: Perform base backup from master (pg_basebackup)
          become_user: postgres
          command: >-
            pg_basebackup -h {{ groups['postgres_master'][0] }} -D {{ pg_data_dir }} -U {{ pg_repl_user }} -Fp -Xs -P
          environment:
            PGPASSWORD: "{{ pg_repl_password }}"

        - name: Create standby.signal (Postgres12+)
          file:
            path: "{{ pg_data_dir }}/standby.signal"
            state: touch
            owner: postgres
            group: postgres

        - name: Create primary_conninfo to connect to master
          copy:
            dest: "{{ pg_data_dir }}/postgresql.auto.conf"
            owner: postgres
            group: postgres
            mode: '0600'
            content: |
              primary_conninfo = 'host={{ groups['postgres_master'][0] }} user={{ pg_repl_user }} password={{ pg_repl_password }}'

        - name: Start postgres on replica
          systemd:
            name: postgresql
            state: started
      notify: Restart postgresql

  handlers:
    - name: Restart postgresql
      systemd:
        name: postgresql
        state: restarted

- name: Redis master/replica + sentinel example
  hosts: redis_master:redis_replica:redis_sentinel
  become: yes
  vars:
    redis_bind: '0.0.0.0'
    redis_replicaof_master: '{{ groups["redis_master"][0] if (groups["redis_master"] | length) > 0 else "" }}'
    redis_master_name: redis-master-1
  tasks:
    - name: Install redis-server
      apt:
        name: redis-server
        state: present
        update_cache: yes

    - name: Ensure redis enabled and started
      systemd:
        name: redis-server
        enabled: yes
        state: started

    - name: Configure redis as replica
      when: inventory_hostname in groups['redis_replica']
      block:
        - name: Configure replicaof in redis.conf
          lineinfile:
            path: /etc/redis/redis.conf
            regexp: '^replicaof\s+'
            line: 'replicaof {{ groups["redis_master"][0] }} 6379'
            state: present
          notify: Restart redis

    - name: Configure sentinel on sentinel nodes
      when: inventory_hostname in groups['redis_sentinel']
      block:
        - name: Create sentinel config
          copy:
            dest: /etc/redis/sentinel.conf
            owner: redis
            group: redis
            mode: '0644'
            content: |
              port 26379
              dir /tmp
              sentinel monitor {{ redis_master_name }} {{ groups['redis_master'][0] }} 6379 2
              sentinel down-after-milliseconds {{ redis_master_name }} 5000
              sentinel failover-timeout {{ redis_master_name }} 15000
              sentinel parallel-syncs {{ redis_master_name }} 1
          notify: Restart redis-sentinel

  handlers:
    - name: Restart redis
      systemd:
        name: redis-server
        state: restarted
    - name: Restart redis-sentinel
      systemd:
        name: redis-sentinel
        state: restarted
```
