#!/usr/bin/env bash
# =============================================================================
# validate_migration.sh
# Purpose: Compare row counts between Cloud SQL source and RDS target
#          to verify DMS full-load + CDC completeness before cutover.
#
# Run from any machine with network access to both databases
# (e.g., the destination-test-instance which has SG access to both).
# =============================================================================
set -euo pipefail

# --- Source (Cloud SQL via VPN tunnel) ---
SRC_HOST="${CLOUD_SQL_HOST}"
SRC_USER="${CLOUD_SQL_USER}"
SRC_PASS="${CLOUD_SQL_PASS}"
SRC_DB="madmax"

# --- Target (RDS via private subnet) ---
DST_HOST="${RDS_ENDPOINT}"
DST_USER="${RDS_USER}"
DST_PASS="${RDS_PASSWORD}"
DST_DB="destinationdb"

TABLES=("regions" "categories" "customers" "products" "warehouses" "inventory" "orders" "order_items")

echo "============================================================"
echo "  DMS Migration Validation — Row Count Comparison"
echo "  Source: Cloud SQL ($SRC_DB @ $SRC_HOST)"
echo "  Target: RDS MySQL ($DST_DB @ $DST_HOST)"
echo "  Time:   $(date -u)"
echo "============================================================"
printf "%-20s %12s %12s %10s\n" "TABLE" "SOURCE" "TARGET" "DELTA"
printf "%-20s %12s %12s %10s\n" "-----" "------" "------" "-----"

PASS=0
FAIL=0

for TABLE in "${TABLES[@]}"; do
  SRC_COUNT=$(mysql -h"$SRC_HOST" -u"$SRC_USER" -p"$SRC_PASS" "$SRC_DB" \
    -sNe "SELECT COUNT(*) FROM ${TABLE}" 2>/dev/null || echo "ERROR")
  DST_COUNT=$(mysql -h"$DST_HOST" -u"$DST_USER" -p"$DST_PASS" "$DST_DB" \
    -sNe "SELECT COUNT(*) FROM ${TABLE}" 2>/dev/null || echo "ERROR")

  if [[ "$SRC_COUNT" == "ERROR" || "$DST_COUNT" == "ERROR" ]]; then
    printf "%-20s %12s %12s %10s\n" "$TABLE" "$SRC_COUNT" "$DST_COUNT" "ERR"
    FAIL=$((FAIL + 1))
  elif [[ "$SRC_COUNT" -eq "$DST_COUNT" ]]; then
    printf "%-20s %12d %12d %10s\n" "$TABLE" "$SRC_COUNT" "$DST_COUNT" "✓ MATCH"
    PASS=$((PASS + 1))
  else
    DELTA=$((DST_COUNT - SRC_COUNT))
    printf "%-20s %12d %12d %10d\n" "$TABLE" "$SRC_COUNT" "$DST_COUNT" "✗ $DELTA"
    FAIL=$((FAIL + 1))
  fi
done

echo "============================================================"
echo "  PASSED: $PASS / $((PASS + FAIL))"

if [[ $FAIL -gt 0 ]]; then
  echo "  FAILED: $FAIL tables have row count mismatches"
  echo "  DO NOT proceed with cutover until all tables match."
  exit 1
else
  echo "  All tables match. Safe to proceed with cutover."
  exit 0
fi
