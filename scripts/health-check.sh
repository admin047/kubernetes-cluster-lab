#!/bin/bash
# Kubernetes 集群健康检查脚本
# 用途: 检查集群和节点的健康状态

set -e

echo "========================================"
echo "Kubernetes 集群健康检查"
echo "========================================"

# 检查集群连接
echo "\n1️⃣  检查集群连接..."
if kubectl cluster-info &> /dev/null; then
    echo "   ✅ 集群连接正常"
else
    echo "   ❌ 集群连接失败"
    exit 1
fi

# 检查节点状态
echo "\n2️⃣  检查节点状态..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
READY_COUNT=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
echo "   节点总数: $NODE_COUNT"
echo "   就绪节点: $READY_COUNT"

if [ $NODE_COUNT -eq $READY_COUNT ]; then
    echo "   ✅ 所有节点就绪"
else
    echo "   ⚠️  存在未就绪节点"
fi

# 检查 Pod 状态
echo "\n3️⃣  检查 Pod 状态..."
POD_COUNT=$(kubectl get pods --all-namespaces --no-headers | wc -l)
RUNNING_COUNT=$(kubectl get pods --all-namespaces --no-headers | grep "Running" | wc -l)
echo "   Pod 总数: $POD_COUNT"
echo "   运行中: $RUNNING_COUNT"

if [ $POD_COUNT -eq $RUNNING_COUNT ]; then
    echo "   ✅ 所有 Pod 运行正常"
else
    echo "   ⚠️  存在异常 Pod"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running
fi

# 检查存储类
echo "\n4️⃣  检查存储类..."
if kubectl get storageclass &> /dev/null; then
    echo "   ✅ 存储类已配置"
    kubectl get storageclass
else
    echo "   ⚠️  未找到存储类"
fi

echo "\n========================================"
echo "✅ 健康检查完成"
echo "========================================"
