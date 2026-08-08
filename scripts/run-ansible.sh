#!/bin/bash
# 在 scripts 目录下运行 Ansible Playbooks 的辅助脚本
set -e

BASEDIR=$(dirname "$0")
INVENTORY="$BASEDIR/hosts"

if [ $# -lt 1 ]; then
  echo "使用: $0 <playbook.yml> [--check]"
  echo "示例: $0 system-check.yml"
  exit 1
fi

PLAYBOOK="$1"
EXTRA_ARGS="${2:-}" 

if [ ! -f "$BASEDIR/$PLAYBOOK" ]; then
  echo "未找到 playbook: $BASEDIR/$PLAYBOOK"
  exit 1
fi

ansible-playbook -i "$INVENTORY" "$BASEDIR/$PLAYBOOK" $EXTRA_ARGS
