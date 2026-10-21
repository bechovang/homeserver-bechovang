#!/usr/bin/env bash
# Homelab backup: Dokploy Postgres dumps + host configs.
# Installed at /usr/local/sbin/homelab-backup.sh, run by homelab-backup.timer (02:30).
# Usage: homelab-backup.sh [--verify]
#   --verify : additionally restore the newest dump into a throwaway DB and drop it.
set -euo pipefail
umask 077

ROOT=/data/backups
PG_DIR="$ROOT/postgres"
WEEKLY_DIR="$PG_DIR/weekly"
MYSQL_DIR="$ROOT/mysql"
MYSQL_WEEKLY_DIR="$MYSQL_DIR/weekly"
CFG_DIR="$ROOT/configs"
LOG_PREFIX="homelab-backup"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$LOG_PREFIX" "$*"; }

mkdir -p "$PG_DIR" "$WEEKLY_DIR" "$MYSQL_DIR" "$MYSQL_WEEKLY_DIR" "$CFG_DIR"
chmod 700 "$ROOT" "$PG_DIR" "$WEEKLY_DIR" "$MYSQL_DIR" "$MYSQL_WEEKLY_DIR" "$CFG_DIR"

# --- Postgres containers (Dokploy metadata + any future app DBs) ---
mapfile -t PGS < <(docker ps --format '{{.ID}} {{.Names}} {{.Image}}' |
  awk '$3 ~ /^postgres:/ {print $1"|"$2"|"$3}')

if ((${#PGS[@]} == 0)); then
  log "WARN no postgres container found"
fi

for entry in "${PGS[@]}"; do
  IFS='|' read -r cid cname image <<<"$entry"
  user=$(docker exec "$cid" printenv POSTGRES_USER 2>/dev/null || true)
  [[ -n "$user" ]] || user=dokploy
  if ! dbs=$(docker exec "$cid" psql -U "$user" -d postgres -tAc \
      "select datname from pg_database where datname not in ('template0','template1')" 2>/dev/null); then
    user=postgres
    dbs=$(docker exec "$cid" psql -U postgres -d postgres -tAc \
      "select datname from pg_database where datname not in ('template0','template1')")
  fi
  for db in $dbs; do
    out="$PG_DIR/${cname}__${db}.dump"
    tmp="$out.tmp"
    docker exec "$cid" pg_dump -U "$user" -Fc -d "$db" >"$tmp"
    mv -f "$tmp" "$out"
    # keep the Sunday dump in the weekly tier
    if [[ "$(date +%u)" == "7" ]]; then
      cp -f "$out" "$WEEKLY_DIR/${cname}__${db}.dump"
    fi
    log "postgres dump ok: $out ($(du -h "$out" | cut -f1))"
  done
done

# daily tier: 7 days, weekly tier: 4 weeks
find "$PG_DIR" -maxdepth 1 -type f -name '*.dump' -mtime +7 -delete
find "$WEEKLY_DIR" -maxdepth 1 -type f -name '*.dump' -mtime +28 -delete

# --- MySQL containers (app DBs, e.g. StorageHub) ---
mkdir -p "$MYSQL_DIR" "$MYSQL_WEEKLY_DIR"
mapfile -t MYSQLS < <(docker ps --format '{{.ID}} {{.Names}} {{.Image}}' |
  awk '$3 ~ /^mysql:/ {print $1"|"$2}')

for entry in "${MYSQLS[@]}"; do
  IFS='|' read -r cid cname <<<"$entry"
  rootpw=$(docker exec "$cid" printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true)
  if [[ -z "$rootpw" ]]; then
    log "WARN mysql container $cname has no MYSQL_ROOT_PASSWORD, skip"
    continue
  fi
  dbs=$(docker exec -e MYSQL_PWD="$rootpw" "$cid" mysql -uroot -N -e "show databases" 2>/dev/null |
    grep -Ev '^(information_schema|performance_schema|mysql|sys)$' || true)
  for db in $dbs; do
    out="$MYSQL_DIR/${cname}__${db}.sql.gz"
    tmp="$out.tmp"
    # no --databases: dump phải restore được vào DB tạm (không có USE/CREATE DATABASE)
    docker exec -e MYSQL_PWD="$rootpw" "$cid" mysqldump -uroot \
      --single-transaction --quick --routines --triggers "$db" |
      gzip -c >"$tmp"
    mv -f "$tmp" "$out"
    if [[ "$(date +%u)" == "7" ]]; then
      cp -f "$out" "$MYSQL_WEEKLY_DIR/${cname}__${db}.sql.gz"
    fi
    log "mysql dump ok: $out ($(du -h "$out" | cut -f1))"
  done
done

find "$MYSQL_DIR" -maxdepth 1 -type f -name '*.sql.gz' -mtime +7 -delete
find "$MYSQL_WEEKLY_DIR" -maxdepth 1 -type f -name '*.sql.gz' -mtime +28 -delete

# --- Host configs (contain secrets: dokploy env/certs, sshd, netplan) ---
cfg="$CFG_DIR/homelab-configs_$(date +%F).tar.gz"
tmp_cfg="$cfg.tmp"
tar -czf "$tmp_cfg" \
  -C / \
  etc/dokploy \
  etc/netplan \
  etc/docker/daemon.json \
  etc/smartd.conf \
  etc/fail2ban \
  etc/ssh/sshd_config.d \
  2>/dev/null || true
mv -f "$tmp_cfg" "$cfg"
chmod 600 "$cfg"
log "configs archived: $cfg ($(du -h "$cfg" | cut -f1))"

find "$CFG_DIR" -maxdepth 1 -type f -name 'homelab-configs_*.tar.gz' -mtime +14 -delete

# --- Optional restore drill ---
if [[ "${1:-}" == "--verify" ]]; then
  newest=$(ls -t "$PG_DIR"/*.dump 2>/dev/null | head -1)
  if [[ -z "$newest" ]]; then
    log "VERIFY FAIL no dump found"
    exit 1
  fi
  cname=$(basename "$newest" | cut -d_ -f1)
  cid=$(docker ps -q -f "name=$cname" | head -1)
  user=$(docker exec "$cid" printenv POSTGRES_USER || echo dokploy)
  probe="restore_check_$$"
  docker exec "$cid" psql -U "$user" -d postgres -v ON_ERROR_STOP=1 -qc "create database \"$probe\""
  docker exec -i "$cid" pg_restore -U "$user" -d "$probe" --no-owner <"$newest"
  tables=$(docker exec "$cid" psql -U "$user" -d "$probe" -tAc \
    "select count(*) from information_schema.tables where table_schema='public'")
  docker exec "$cid" psql -U "$user" -d postgres -qc "drop database \"$probe\""
  if [[ "$tables" -lt 1 ]]; then
    log "VERIFY FAIL $newest restored 0 tables"
    exit 1
  fi
  log "VERIFY OK $newest -> $tables tables in $probe (dropped)"
fi

if [[ "${1:-}" == "--verify" ]]; then
  newest_mysql=$(ls -t "$MYSQL_DIR"/*.sql.gz 2>/dev/null | head -1)
  if [[ -n "$newest_mysql" ]]; then
    cname=$(basename "$newest_mysql" | cut -d_ -f1)
    cid=$(docker ps -q -f "name=$cname" | head -1)
    rootpw=$(docker exec "$cid" printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true)
    if [[ -n "$rootpw" ]]; then
      probe="restore_check_$$"
      docker exec -e MYSQL_PWD="$rootpw" "$cid" mysql -uroot -e "create database \`$probe\`"
      zcat "$newest_mysql" | docker exec -i -e MYSQL_PWD="$rootpw" "$cid" mysql -uroot "$probe"
      tables=$(docker exec -e MYSQL_PWD="$rootpw" "$cid" mysql -uroot -N -e \
        "select count(*) from information_schema.tables where table_schema='$probe'")
      docker exec -e MYSQL_PWD="$rootpw" "$cid" mysql -uroot -e "drop database \`$probe\`"
      if [[ "$tables" -lt 1 ]]; then
        log "VERIFY FAIL $newest_mysql restored 0 tables"
        exit 1
      fi
      log "VERIFY OK $newest_mysql -> $tables tables in $probe (dropped)"
    fi
  fi
fi

log "done"
