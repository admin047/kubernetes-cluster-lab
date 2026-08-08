#!/bin/bash
# Kubernetes 应用部署脚本
# 用途: 简化应用部署流程

set -e

if [ $# -lt 2 ]; then
    echo "使用方法: $0 <app-name> <namespace> [image-tag]"
    echo "示例: $0 myapp production v1.0.0"
    exit 1
fi

APP_NAME=$1
NAMESPACE=$2
IMAGE_TAG=${3:-latest}

echo "========================================"
echo "部署应用: $APP_NAME"
echo "命名空间: $NAMESPACE"
echo "镜像标签: $IMAGE_TAG"
echo "========================================"

# 检查命名空间是否存在
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "❌ 命名空间不存在: $NAMESPACE"
    exit 1
fi

echo "✅ 命名空间存在"
echo "\n部署中..."

# 应用 manifests
kubectl apply -f ./manifests/$APP_NAME/ -n $NAMESPACE

echo "\n✅ 应用部署完成！"
echo "\n检查部署状态:"
kubectl rollout status deployment/$APP_NAME -n $NAMESPACE
