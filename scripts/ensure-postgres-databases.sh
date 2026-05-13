#!/usr/bin/env bash
# Idempotent: ensures every POSTGRES_DB declared in the two production .postgres
# env files exists on the running postgres service. Creates missing LOGIN roles
# (with passwords from the same files) when they differ from the merged admin
# user. Intended to run from the repo root on the host or inside CI/EC2 after
# `docker compose up -d postgres`.
#
# Usage:
#   ./scripts/ensure-postgres-databases.sh
# Optional env:
#   REPO_ROOT            default: parent of scripts/
#   COSMETIC_POSTGRES_ENV default: $REPO_ROOT/cosmetic/.envs/.production/.postgres
#   CODEHELP_POSTGRES_ENV default: $REPO_ROOT/codehelp/.envs/.production/.postgres
#   COMPOSE_OPTS         default: "-f production.yml" (space-separated flags, e.g.
#                        "-f production.yml -f compose.override.yml")

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COSMETIC_POSTGRES_ENV="${COSMETIC_POSTGRES_ENV:-$REPO_ROOT/cosmetic/.envs/.production/.postgres}"
CODEHELP_POSTGRES_ENV="${CODEHELP_POSTGRES_ENV:-$REPO_ROOT/codehelp/.envs/.production/.postgres}"
COMPOSE_OPTS="${COMPOSE_OPTS:--f production.yml}"

cd "$REPO_ROOT"

read -r -a COMPOSE_ARGS <<< "$COMPOSE_OPTS"

if [[ ! -f "$COSMETIC_POSTGRES_ENV" ]] || [[ ! -f "$CODEHELP_POSTGRES_ENV" ]]; then
  echo "ensure-postgres-databases: missing env file(s)" >&2
  echo "  cosmetic: $COSMETIC_POSTGRES_ENV" >&2
  echo "  codehelp: $CODEHELP_POSTGRES_ENV" >&2
  exit 1
fi

get_var() {
  local file="$1" key="$2" line val
  line="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n1 || true)"
  [[ -z "$line" ]] && return 0
  val="${line#*=}"
  val="${val%$'\r'}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ ${#val} -ge 2 ]] && [[ ${val:0:1} == '"' ]] && [[ ${val: -1} == '"' ]]; then
    val="${val:1:-1}"
  fi
  printf '%s' "$val"
}

merge_var() {
  local key="$1" h c
  h="$(get_var "$CODEHELP_POSTGRES_ENV" "$key")"
  c="$(get_var "$COSMETIC_POSTGRES_ENV" "$key")"
  if [[ -n "$h" ]]; then printf '%s' "$h"; else printf '%s' "$c"; fi
}

is_safe_ident() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

sql_escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

admin_user="$(merge_var POSTGRES_USER)"
admin_pass="$(merge_var POSTGRES_PASSWORD)"

if [[ -z "$admin_user" ]] || [[ -z "$admin_pass" ]]; then
  echo "ensure-postgres-databases: merged POSTGRES_USER / POSTGRES_PASSWORD is empty" >&2
  exit 1
fi

c_db="$(get_var "$COSMETIC_POSTGRES_ENV" POSTGRES_DB)"
c_user="$(get_var "$COSMETIC_POSTGRES_ENV" POSTGRES_USER)"
c_pass="$(get_var "$COSMETIC_POSTGRES_ENV" POSTGRES_PASSWORD)"
h_db="$(get_var "$CODEHELP_POSTGRES_ENV" POSTGRES_DB)"
h_user="$(get_var "$CODEHELP_POSTGRES_ENV" POSTGRES_USER)"
h_pass="$(get_var "$CODEHELP_POSTGRES_ENV" POSTGRES_PASSWORD)"

declare -A SEEN_DB=()

add_target() {
  local db="$1" owner="$2" pass="$3"
  [[ -z "$db" ]] && return 0
  if ! is_safe_ident "$db"; then
    echo "ensure-postgres-databases: unsafe POSTGRES_DB: $db" >&2
    exit 1
  fi
  if [[ -n "$owner" ]] && ! is_safe_ident "$owner"; then
    echo "ensure-postgres-databases: unsafe role name: $owner" >&2
    exit 1
  fi
  if [[ -z "${SEEN_DB[$db]+x}" ]]; then
    SEEN_DB["$db"]=1
    TARGET_DBS+=("$db")
    TARGET_OWNER+=("$owner")
    TARGET_PASS+=("$pass")
  fi
}

TARGET_DBS=()
TARGET_OWNER=()
TARGET_PASS=()

add_target "$c_db" "$c_user" "$c_pass"
add_target "$h_db" "$h_user" "$h_pass"

if [[ ${#TARGET_DBS[@]} -eq 0 ]]; then
  echo "ensure-postgres-databases: no POSTGRES_DB in env files; nothing to do"
  exit 0
fi

wait_for_postgres() {
  local i
  for i in $(seq 1 60); do
    if PGPASSWORD="$admin_pass" docker compose "${COMPOSE_ARGS[@]}" exec -T \
      -e "PGPASSWORD=$admin_pass" postgres \
      pg_isready -U "$admin_user" -d postgres -q 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "ensure-postgres-databases: postgres did not become ready in time" >&2
  return 1
}

psql_admin() {
  PGPASSWORD="$admin_pass" docker compose "${COMPOSE_ARGS[@]}" exec -T \
    -e "PGPASSWORD=$admin_pass" postgres \
    psql -v ON_ERROR_STOP=1 -U "$admin_user" -d postgres "$@"
}

wait_for_postgres

for i in "${!TARGET_DBS[@]}"; do
  db="${TARGET_DBS[$i]}"
  owner="${TARGET_OWNER[$i]}"
  pass="${TARGET_PASS[$i]}"

  if [[ -n "$owner" ]] && [[ "$owner" != "$admin_user" ]]; then
    exists="$(psql_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname='$(sql_escape_literal "$owner")'" | tr -d '[:space:]' || true)"
    if [[ "$exists" != "1" ]]; then
      if [[ -z "$pass" ]]; then
        echo "ensure-postgres-databases: role $owner is missing but POSTGRES_PASSWORD is empty in env" >&2
        exit 1
      fi
      lit="$(sql_escape_literal "$pass")"
      psql_admin -c "CREATE ROLE ${owner} LOGIN PASSWORD '${lit}';"
    fi
  fi

  db_exists="$(psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='$(sql_escape_literal "$db")'" | tr -d '[:space:]' || true)"
  if [[ "$db_exists" != "1" ]]; then
    eff_owner="${owner:-$admin_user}"
    if [[ -z "$eff_owner" ]]; then
      eff_owner="$admin_user"
    fi
    psql_admin -c "CREATE DATABASE ${db} OWNER ${eff_owner};"
    echo "ensure-postgres-databases: created database $db (owner $eff_owner)"
  else
    echo "ensure-postgres-databases: database $db already exists"
  fi
done
