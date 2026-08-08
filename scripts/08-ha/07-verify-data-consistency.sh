#!/bin/bash
# scripts/08-ha/07-verify-data-consistency.sh
# 用途：验证 PostgreSQL 主从数据一致性（行数对比、复制状态、LSN 差异提示）
# 用法： bash 07-verify-data-consistency.sh <primary-host> <replica-host> <db-name> [pg_user]

set -euo pipefail
PRIMARY=${1:-127.0.0.1}
REPLICA=${2:-127.0.0.1}
DB=${3:-postgres}
PG_USER=${4:-postgres}

echo "Checking replication status on primary: $PRIMARY"
ssh $PRIMARY sudo -u postgres psql -c "SELECT client_addr, state, sync_priority, sync_state FROM pg_stat_replication;" || true

echo "Checking if replica is in recovery (should be true):"
ssh $REPLICA sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Compare table row counts for common tables
TMP='/tmp/pg_table_list.txt'
ssh $PRIMARY sudo -u postgres psql -d "$DB" -Atc "SELECT tablename FROM pg_tables WHERE schemaname='public';" > $TMP

echo "Comparing row counts for database $DB"
while read -r t; do
  pcount=$(ssh $PRIMARY sudo -u postgres psql -d "$DB" -Atc "SELECT count(*) FROM \"$t\";" 2>/dev/null || echo "-")
  rcount=$(ssh $REPLICA sudo -u postgres psql -d "$DB" -Atc "SELECT count(*) FROM \"$t\";" 2>/dev/null || echo "-")
  if [ "$pcount" != "$rcount" ]; then
    echo "[DIFF] Table $t : primary=$pcount replica=$rcount"
  else
    echo "[OK]   Table $t : count=$pcount"
  fi
done < $TMP

echo "Check LSN positions on primary and replica"
ssh $PRIMARY sudo -u postgres psql -Atc "SELECT pg_current_wal_lsn();" > /tmp/primary_lsn
ssh $REPLICA sudo -u postgres psql -Atc "SELECT pg_last_wal_replay_lsn();" > /tmp/replica_lsn
p_lsn=$(cat /tmp/primary_lsn)
r_lsn=$(cat /tmp/replica_lsn)

echo "Primary LSN: $p_lsn"
echo "Replica LSN: $r_lsn"

if [ "$p_lsn" = "$r_lsn" ]; then
  echo "LSN equal: replica caught up"
else
  echo "LSN differ: replica may lag. Check pg_stat_replication on primary for replay_lag or use pg_wal_lsn_diff to measure" 
fi

# cleanup
rm -f $TMP /tmp/primary_lsn /tmp/replica_lsn
