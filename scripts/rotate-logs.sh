#!/bin/bash
# 日志切割脚本（示例）
# 会将 /var/log/k8s-apps/*.log 按天归档并保留 7 天
LOG_DIR="/var/log/k8s-apps"
ARCHIVE_DIR="/var/log/k8s-apps/archive"
RETENTION_DAYS=7

mkdir -p "$ARCHIVE_DIR"

find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" | while read -r f; do
  base=$(basename "$f")
  ts=$(date +%Y%m%d_%H%M%S)
  gzip -c "$f" > "$ARCHIVE_DIR/${base}. ${ts}.gz"
  : > "$f"
done

# 删除旧文件
find "$ARCHIVE_DIR" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \;

echo "日志切割完成"
