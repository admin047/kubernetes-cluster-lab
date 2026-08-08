#!/bin/bash
# ETCD 数据备份脚本
# 用途: 备份 Kubernetes ETCD 数据库

set -e

BACKUP_DIR="./etcd-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/etcd-backup-$TIMESTAMP.db"

echo "========================================"
echo "ETCD 数据备份"
echo "========================================"

# 创建备份目录
mkdir -p $BACKUP_DIR

echo "\n备份位置: $BACKUP_FILE"

# 执行备份
echo "\n正在备份 ETCD..."
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save $BACKUP_FILE

echo "\n✅ ETCD 备份完成"
echo "备份文件: $BACKUP_FILE"
echo "文件大小: $(du -h $BACKUP_FILE | cut -f1)"
