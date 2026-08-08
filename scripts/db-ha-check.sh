#!/bin/bash
# DB HA 检查脚本（示例）
# 适用于 MySQL/Redis 基本可用性检测
set -euo pipefail

echo "检查 MySQL 服务"
if kubectl get svc -n database mysql 1>/dev/null 2>&1; then
  kubectl get pods -n database -l app=mysql -o wide
else
  echo "未找到 MySQL 服务 (namespace: database, svc: mysql)"
fi

echo "检查 Redis 服务"
if kubectl get svc -n database redis 1>/dev/null 2>&1; then
  kubectl get pods -n database -l app=redis -o wide
else
  echo "未找到 Redis 服务 (namespace: database, svc: redis)"
fi

echo "建议：通过故障注入（停止主节点）验证复制与故障切换"
