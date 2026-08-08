#!/bin/bash
# Kubernetes 集群初始化脚本
# 用途: 自动化初始化 Kubernetes 集群环境

set -e

echo "========================================"
echo "Kubernetes 集群初始化"
echo "========================================"

# 检查 kubectl 是否安装
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    exit 1
fi

echo "✅ kubectl 已安装"

# 获取集群信息
echo "\n📋 集群信息:"
kubectl cluster-info

# 创建命名空间
echo "\n📦 创建默认命名空间..."
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "\n✅ 集群初始化完成！"
