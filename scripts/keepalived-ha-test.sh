#!/bin/bash
# Keepalived HA 故障转移自动化测试脚本（示例）
# 用法: ./scripts/keepalived-ha-test.sh <vip> <peer-ip>
set -euo pipefail
VIP="$1"
PEER="$2"

if [ -z "$VIP" ] || [ -z "$PEER" ]; then
  echo "用法: $0 <vip> <peer-ip>"
  exit 1
fi

echo "检查本机是否持有 VIP"
ip addr show | grep "$VIP" && echo "本机持有 VIP" || echo "本机未持有 VIP"

echo "向 peer 发起 SSH 停止 keepalived 测试（需要免密）"
ssh root@"$PEER" 'systemctl stop keepalived || true'

sleep 5

echo "检测 VIP 是否漂移到备机"
ip -brief addr show | grep "$VIP" || echo "请在备机确认 VIP 是否被添加"

# 恢复
ssh root@"$PEER" 'systemctl start keepalived || true'

echo "测试完成，已尝试恢复 peer keepalived 服务"
