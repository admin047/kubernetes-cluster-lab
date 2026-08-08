#!/bin/bash
# 镜像扫描（Trivy）脚本
# 用法: ./scripts/trivy-scan.sh <image>
set -euo pipefail
IMAGE="${1:-}
"
REPORT_DIR="./trivy-reports"
mkdir -p "$REPORT_DIR"

if [ -z "$IMAGE" ]; then
  echo "用法: $0 <image>
示例: $0 myregistry.local/myapp:latest"
  exit 1
fi

REPORT_FILE="$REPORT_DIR/$(echo "$IMAGE" | sed 's/[^a-zA-Z0-9._-]/_/g').json"

echo "扫描镜像: $IMAGE"
trivy image --exit-code 0 --format json -o "$REPORT_FILE" "$IMAGE"

echo "扫描完成，报告保存在: $REPORT_FILE"

