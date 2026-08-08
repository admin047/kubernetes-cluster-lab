#!/bin/bash
# scripts/08-ha/06-deploy-postgresql-ha.sh
# 说明：交互式/参数化脚本，用于部署 PostgreSQL 主/从（Streaming Replication）
# 使用示例：
#  在主节点执行： bash 06-deploy-postgresql-ha.sh primary
#  在从节点执行： bash 06-deploy-postgresql-ha.sh replica <primary-host> <repl_user> <repl_password>

set -euo pipefail

ROLE=${1:-}
PRIMARY_HOST=${2:-}
REPL_USER=${3:-replicator}
REPL_PASS=${4:-repl_pass}
PG_VERSION=${5:-12}
PG_DATA_DIR=${6:-/var/lib/postgresql/${PG_VERSION}/main}

function usage() {
  cat <<EOF
Usage:
  $0 primary
  $0 replica <primary-host> [repl_user] [repl_password] [pg_version] [data_dir]
EOF
  exit 1
}

if [ -z "$ROLE" ]; then
  usage
fi

if [ "$ROLE" = "primary" ]; then
  echo "Configuring PostgreSQL primary (local)"
  echo "Ensure postgresql-${PG_VERSION} is installed and running"
  # Update postgresql.conf params
  CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
  echo "Setting wal_level, max_wal_senders, archive_mode..."
  sudo mkdir -p "$CONF_DIR/postgres-conf.d" || true
  sudo tee "$CONF_DIR/postgres-conf.d/ha.conf" > /dev/null <<EOF
wal_level = 'replica'
max_wal_senders = 5
wal_keep_segments = 64
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/archived/%f && cp %p /var/lib/postgresql/archived/%f'
EOF
  sudo systemctl restart postgresql
  echo "Create replication user: $REPL_USER"
  sudo -u postgres psql -c "CREATE ROLE $REPL_USER REPLICATION LOGIN ENCRYPTED PASSWORD '$REPL_PASS';" || true
  echo "Primary configuration complete."
  exit 0
fi

if [ "$ROLE" = "replica" ]; then
  if [ -z "$PRIMARY_HOST" ]; then
    usage
  fi
  echo "Configuring PostgreSQL replica to follow $PRIMARY_HOST"
  echo "This will stop postgres, clean data dir ($PG_DATA_DIR) and do pg_basebackup from primary."
  read -p "Are you sure you want to continue? This will destroy local data directory (yes/NO): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted by user"
    exit 1
  fi

  sudo systemctl stop postgresql
  sudo rm -rf "$PG_DATA_DIR"
  sudo mkdir -p "$PG_DATA_DIR"
  sudo chown -R postgres:postgres "$PG_DATA_DIR"

  echo "Running pg_basebackup from $PRIMARY_HOST"
  export PGPASSWORD="$REPL_PASS"
  sudo -u postgres pg_basebackup -h "$PRIMARY_HOST" -D "$PG_DATA_DIR" -U "$REPL_USER" -Fp -Xs -P || { echo "pg_basebackup failed"; exit 1; }

  echo "Creating standby.signal and primary_conninfo"
  sudo -u postgres touch "$PG_DATA_DIR/standby.signal"
  sudo tee "$PG_DATA_DIR/postgresql.auto.conf" > /dev/null <<EOF
primary_conninfo = 'host=$PRIMARY_HOST user=$REPL_USER password=$REPL_PASS'
EOF
  sudo chown postgres:postgres "$PG_DATA_DIR/postgresql.auto.conf"

  sudo systemctl start postgresql
  echo "Replica started. Verify with: sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'"
  exit 0
fi

usage
