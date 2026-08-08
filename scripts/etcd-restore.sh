#!/bin/bash
# ETCD 恢复脚本
# 用法: ./scripts/etcd-restore.sh <snapshot-file> <data-dir> <initial-cluster>
set -euo pipefail

SNAPSHOT_FILE="$1"
DATA_DIR="${2:-/var/lib/etcd}
"
INITIAL_CLUSTER="$3"

if [ -z "$SNAPSHOT_FILE" ]; then
  echo "使用: $0 <snapshot-file> <data-dir> <initial-cluster>"
  exit 1
fi

echo "停止 kube-apiserver 以及关联 etcd 服务（请根据你的环境调整）"
# systemctl stop kube-apiserver || true
# systemctl stop etcd || true

echo "恢复 snapshot: $SNAPSHOT_FILE 到 $DATA_DIR"
sudo ETCDCTL_API=3 etcdctl snapshot restore "$SNAPSHOT_FILE" \
  --data-dir "$DATA_DIR" \
  --name "etcd-restore" \
  --initial-cluster "$INITIAL_CLUSTER" \
  --initial-cluster-token "etcd-restore-token" \
  --initial-advertise-peer-urls http://127.0.0.1:2380

echo "恢复完成，请根据 etcd 启动方式将数据目录移动到正确位置并重启 etcd 服务"

echo "建议检查: etcdctl --endpoints=127.0.0.1:2379 endpoint status"
