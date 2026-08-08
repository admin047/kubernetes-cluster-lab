#!/bin/bash
# OPA/Policy 检查示例（使用 conftest 或 opa）
set -euo pipefail

MANIFEST_DIR="./manifests"

if ! command -v conftest >/dev/null 2>&1; then
  echo "请先安装 conftest 或 opa"
  exit 1
fi

for f in $(find "$MANIFEST_DIR" -name "*.yaml" -o -name "*.yml"); do
  echo "检查 $f"
  conftest test "$f" || true
done
