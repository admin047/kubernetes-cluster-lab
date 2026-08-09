Keepalived + MySQL 主从高可用实践
1. 项目介绍

本项目基于 Linux 环境搭建数据库高可用架构，通过 Keepalived + MySQL 主从复制 实现数据库服务故障切换能力。

主要实现：

使用 Keepalived 提供 VIP 高可用入口
使用 VRRP 协议实现主备节点自动切换
使用 MySQL 主从复制实现数据同步
配置复制账号与权限隔离
实践数据库等保三权分立权限模型

整体架构：

                  Client
                    |
                    |
              Virtual IP(VIP)
              192.168.76.100
                    |
          -----------------------
          |                     |
          |                     |
     MySQL Master          MySQL Slave
     192.168.76.4          192.168.76.10
          |
          |
      Binary Log
          |
          ↓
      Relay Log
          |
          ↓
     数据同步
2. 环境信息
节点规划
节点	IP	角色
mysql-master	192.168.76.4	MySQL主库
mysql-slave	192.168.76.10	MySQL从库
VIP	192.168.76.100	业务访问地址

系统：

Ubuntu 24.04 LTS

数据库：

MySQL 8.0.46
3. Keepalived 高可用配置
3.1 安装 Keepalived

两台服务器执行：

apt update

apt install keepalived -y

查看版本：

keepalived --version
4. Master 节点配置

文件：

vim /etc/keepalived/keepalived.conf

配置：

global_defs {

    router_id MYSQL_MASTER

}


vrrp_instance VI_1 {

    state MASTER

    interface ens33

    virtual_router_id 51

    priority 100

    advert_int 1


    authentication {

        auth_type PASS

        auth_pass 123456

    }


    virtual_ipaddress {

        192.168.76.100

    }

}
5. Slave节点配置
global_defs {

    router_id MYSQL_SLAVE

}


vrrp_instance VI_1 {


    state BACKUP


    interface ens33


    virtual_router_id 51


    priority 90


    advert_int 1



    authentication {

        auth_type PASS

        auth_pass 123456

    }



    virtual_ipaddress {

        192.168.76.100

    }

}
6. 启动 Keepalived

两台执行：

systemctl enable keepalived

systemctl start keepalived

查看：

systemctl status keepalived
验证 VIP

Master:

ip addr

查看：

192.168.76.100

说明 MASTER 获取 VIP。

Slave：

ip addr

没有 VIP。

7. MySQL 主从复制
7.1 主库配置

编辑：

vim /etc/mysql/mysql.conf.d/mysqld.cnf

添加：

[mysqld]

server-id=1

log-bin=mysql-bin

binlog_format=ROW

重启：

systemctl restart mysql

验证：

SHOW VARIABLES LIKE 'log_bin';

SHOW VARIABLES LIKE 'server_id';
8. 创建复制用户

Master：

CREATE USER 'repl'
@'192.168.76.10'
IDENTIFIED BY '123456';


GRANT REPLICATION SLAVE
ON *
.*
TO 'repl'@'192.168.76.10';


FLUSH PRIVILEGES;

查看：

SHOW GRANTS FOR 'repl'@'192.168.76.10';

结果：

GRANT REPLICATION SLAVE ON *.*
9. 获取主库 Binlog 信息

Master：

SHOW MASTER STATUS;

示例：

File:
mysql-bin.000001


Position:
1629

记录：

mysql-bin.000001
1629
10. 从库配置

编辑：

vim /etc/mysql/mysql.conf.d/mysqld.cnf

添加：

[mysqld]

server-id=2

relay-log=mysql-relay-bin

重启：

systemctl restart mysql
11. 配置复制

Slave：

CHANGE REPLICATION SOURCE TO


SOURCE_HOST='192.168.76.4',

SOURCE_USER='repl',

SOURCE_PASSWORD='123456',

SOURCE_LOG_FILE='mysql-bin.000001',

SOURCE_LOG_POS=1629;


START REPLICA;
12. 查看主从状态
SHOW REPLICA STATUS\G

成功：

Replica_IO_Running: Yes

Replica_SQL_Running: Yes

同步延迟：

Seconds_Behind_Source: 0
13. 主从复制测试
Master创建数据库
CREATE DATABASE testdb;

Slave：

SHOW DATABASES;

出现：

testdb

表示同步成功。

14. 数据库等保三权分立
权限模型
              MySQL

                |

 ---------------------------------

 |              |                |

DBA       Security Admin     Audit Admin


数据库管理    权限管理          审计查看

创建数据库管理员
CREATE USER
'db_admin'@'%'
IDENTIFIED BY 'Db@123456';

授权：

GRANT

SELECT,
INSERT,
UPDATE,
DELETE,
CREATE,
ALTER,
DROP

ON *.*

TO
'db_admin'@'%';
创建安全管理员
CREATE USER
'security_admin'@'%'
IDENTIFIED BY 'Sec@123456';

授权：

GRANT CREATE USER
ON *.*
TO 'security_admin'@'%';


GRANT GRANT OPTION
ON *.*
TO 'security_admin'@'%';
创建审计管理员
CREATE USER
'audit_admin'@'%'
IDENTIFIED BY 'Audit@123456';

授权：

GRANT SELECT

ON mysql.*

TO 'audit_admin'@'%';
15. 验证权限隔离

查看权限：

SHOW GRANTS FOR
'db_admin'@'%';


SHOW GRANTS FOR
'security_admin'@'%';


SHOW GRANTS FOR
'audit_admin'@'%';
