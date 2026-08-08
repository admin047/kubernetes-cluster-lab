#!/bin/bash
# scripts/08-ha/run-ha-drill.sh
# Interactive runner to perform HA drill steps in order (Keepalived -> Nginx -> Copy configs -> optional restarts)
# Safe/confirming: asks user before each potentially destructive action.

set -euo pipefail
INVENTORY="$(dirname "$0")/../../hosts"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -f "$INVENTORY" ]; then
  echo "Inventory not found: $INVENTORY"
  exit 1
fi

# helper: get hosts from inventory group
get_group_hosts() {
  local group="$1"
  awk '/^\['"$group"'\]/{flag=1;next}/^\[/{flag=0}flag && NF{print $0}' "$INVENTORY" | while read -r line; do
    ip=$(echo "$line" | sed -n 's/.*ansible_host=\([^ ]*\).*/\1/p')
    if [ -z "$ip" ]; then
      ip=$(echo "$line" | awk '{print $1}')
    fi
    echo "$ip"
  done
}

echo "HA Drill Runner"
echo "Inventory: $INVENTORY"

echo "Detected groups and hosts:"
for g in kubernetes keepalived nginx mysql_master mysql_replica postgres_master postgres_replica redis_master redis_replica redis_sentinel; do
  hosts=$(get_group_hosts "$g" | xargs || true)
  echo "  [$g] $hosts"
done

read -p "Type CONFIRM to proceed with the drill (runs interactive, will copy configs and attempt service restarts): " confirm
if [ "$confirm" != "CONFIRM" ]; then
  echo "Aborted by user"
  exit 0
fi

# Step 1: Deploy Keepalived configs to keepalived group
KEEP_HOSTS=( $(get_group_hosts keepalived) )
if [ ${#KEEP_HOSTS[@]} -eq 0 ]; then
  echo "No keepalived hosts found in inventory. Skipping Keepalived step."
else
  echo "\n== Keepalived Deployment =="
  echo "Will deploy to: ${KEEP_HOSTS[*]}"
  # check config presence
  if [ -f "$ROOT_DIR/configs/keepalived/keepalived-master.conf" ]; then
    echo "Found keepalived-master.conf"
  else
    echo "Missing configs/keepalived/keepalived-master.conf — please create it before running. Skipping Keepalived."
  fi

  for i in "${!KEEP_HOSTS[@]}"; do
    ip=${KEEP_HOSTS[$i]}
    if [ $i -eq 0 ]; then
      conf_src="$ROOT_DIR/configs/keepalived/keepalived-master.conf"
    else
      if [ -f "$ROOT_DIR/configs/keepalived/keepalived-backup.conf" ]; then
        conf_src="$ROOT_DIR/configs/keepalived/keepalived-backup.conf"
      else
        conf_src="$ROOT_DIR/configs/keepalived/keepalived-master.conf"
      fi
    fi
    if [ -f "$conf_src" ]; then
      echo "Copying $conf_src -> root@$ip:/etc/keepalived/keepalived.conf"
      scp "$conf_src" "root@$ip:/etc/keepalived/keepalived.conf"
      if [ -f "$ROOT_DIR/configs/keepalived/check_nginx.sh" ]; then
        scp "$ROOT_DIR/configs/keepalived/check_nginx.sh" "root@$ip:/etc/keepalived/check_nginx.sh"
        ssh "root@$ip" "chmod +x /etc/keepalived/check_nginx.sh || true"
      fi
      echo "Enable & start keepalived on $ip"
      ssh "root@$ip" "systemctl enable --now keepalived || (systemctl start keepalived || true)"
    else
      echo "Config $conf_src not found — skipped host $ip"
    fi
  done
fi

# Step 2: Deploy Nginx LB
NGINX_HOSTS=( $(get_group_hosts nginx) )
if [ ${#NGINX_HOSTS[@]} -eq 0 ]; then
  echo "No nginx hosts found in inventory. Skipping Nginx step."
else
  nginx_host=${NGINX_HOSTS[0]}
  echo "\n== Nginx Deployment =="
  echo "Target nginx host: $nginx_host"
  if [ -f "$ROOT_DIR/configs/nginx/nginx-lb.conf" ]; then
    echo "Copying nginx config to $nginx_host"
    scp "$ROOT_DIR/configs/nginx/nginx-lb.conf" "root@$nginx_host:/etc/nginx/nginx.conf"
    # copy ssl if exists
    if [ -d "$ROOT_DIR/configs/nginx/ssl" ]; then
      scp -r "$ROOT_DIR/configs/nginx/ssl" "root@$nginx_host:/etc/nginx/ssl"
    fi
    ssh "root@$nginx_host" "nginx -t || true; systemctl enable --now nginx || (systemctl start nginx || true)"
  else
    echo "Missing configs/nginx/nginx-lb.conf — skipping Nginx deployment"
  fi
fi

# Step 3: Copy DB/Redis configs (no destructive DB actions unless explicitly confirmed)
echo "\n== Copying DB/Redis configs (no destructive actions by default) =="
# MySQL
MYSQL_MASTER=( $(get_group_hosts mysql_master) )
if [ ${#MYSQL_MASTER[@]} -gt 0 ] && [ -f "$ROOT_DIR/configs/mysql/master.cnf" ]; then
  m=${MYSQL_MASTER[0]}
  echo "Copying MySQL master config to $m"
  scp "$ROOT_DIR/configs/mysql/master.cnf" "root@$m:/etc/my.cnf"
  ssh "root@$m" "systemctl restart mysqld || systemctl restart mysql || true"
else
  echo "MySQL master config not found or mysql_master not set — skipped"
fi

# Postgres
PG_MASTER=( $(get_group_hosts postgres_master) )
PG_REPLICA=( $(get_group_hosts postgres_replica) )
if [ ${#PG_MASTER[@]} -gt 0 ] && [ -f "$ROOT_DIR/configs/postgresql/postgresql-primary.conf" ]; then
  pm=${PG_MASTER[0]}
  echo "Copying Postgres primary config to $pm"
  scp "$ROOT_DIR/configs/postgresql/postgresql-primary.conf" "root@$pm:/etc/postgresql/postgresql-primary.conf"
  ssh "root@$pm" "systemctl restart postgresql || true"
fi
if [ ${#PG_REPLICA[@]} -gt 0 ] && [ -f "$ROOT_DIR/configs/postgresql/postgresql-replica.conf" ]; then
  pr=${PG_REPLICA[0]}
  echo "Copying Postgres replica config to $pr"
  scp "$ROOT_DIR/configs/postgresql/postgresql-replica.conf" "root@$pr:/etc/postgresql/postgresql-replica.conf"
  ssh "root@$pr" "systemctl restart postgresql || true"
fi

# Redis
RED_MASTER=( $(get_group_hosts redis_master) )
if [ ${#RED_MASTER[@]} -gt 0 ] && [ -f "$ROOT_DIR/configs/redis/redis-master.conf" ]; then
  rm=${RED_MASTER[0]}
  echo "Copying Redis master config to $rm"
  scp "$ROOT_DIR/configs/redis/redis-master.conf" "root@$rm:/etc/redis/redis.conf"
  ssh "root@$rm" "systemctl enable --now redis || systemctl start redis || true"
fi

# Final verification prompt
read -p "Drill completed copy steps. Do you want to run verification commands now? (yes/NO): " ver
if [ "$ver" = "yes" ]; then
  echo "Running verification samples..."
  # VIP check on first keepalived host
  if [ ${#KEEP_HOSTS[@]} -gt 0 ]; then
    echo "VIP on master (${KEEP_HOSTS[0]}):"
    ssh "root@${KEEP_HOSTS[0]}" "ip addr show | grep 192.168.76.100 || true"
  fi
  # Nginx check
  if [ ! -z "${nginx_host:-}" ]; then
    ssh "root@$nginx_host" "nginx -t || true; systemctl status nginx --no-pager || true"
    echo "Attempt to curl VIP API endpoint from runner host:"
    curl -k https://192.168.76.100:6443/version || true
  fi
fi

echo "\nHA drill runner finished. Review outputs above."
