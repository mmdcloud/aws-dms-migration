#!/usr/bin/env bash
# =============================================================================
# seed_cloudsql.sh
# Purpose: Populate the Cloud SQL source (madmax DB, us-central1) with
#          the same schema and data as V1+V2 so DMS full-load has rows to copy.
#
# Run this on the GCP compute instance (source-test-instance) BEFORE
# starting the DMS replication task.
#
# Usage:
#   SSH into source-test-instance
#   chmod +x seed_cloudsql.sh && ./seed_cloudsql.sh
# =============================================================================
set -euo pipefail

DB_HOST="${CLOUD_SQL_HOST:-127.0.0.1}"   # Private IP of Cloud SQL instance
DB_PORT="${CLOUD_SQL_PORT:-3306}"
DB_NAME="madmax"
DB_USER="${CLOUD_SQL_USER}"
DB_PASS="${CLOUD_SQL_PASS}"

MYSQL="mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASS} ${DB_NAME}"

echo "[INFO] Connected to Cloud SQL: $DB_HOST/$DB_NAME"

# -----------------------------------------------------------------------
# Verify binlog_format = ROW (required for DMS CDC)
# -----------------------------------------------------------------------
BINLOG_FORMAT=$($MYSQL -sNe "SHOW VARIABLES LIKE 'binlog_format'" | awk '{print $2}')
if [[ "$BINLOG_FORMAT" != "ROW" ]]; then
  echo "[ERROR] binlog_format must be ROW for DMS CDC. Current: $BINLOG_FORMAT"
  echo "        Add database_flags binlog_format=ROW in your Cloud SQL Terraform config."
  exit 1
fi
echo "[OK] binlog_format = $BINLOG_FORMAT"

# -----------------------------------------------------------------------
# Create schema (mirrors V1__baseline_schema.sql)
# -----------------------------------------------------------------------
echo "[INFO] Creating source schema..."
$MYSQL < "$(dirname "$0")/../migrations/V1__baseline_schema.sql"

# -----------------------------------------------------------------------
# Seed reference data (mirrors V2__seed_reference_data.sql)
# -----------------------------------------------------------------------
echo "[INFO] Seeding reference data..."
$MYSQL < "$(dirname "$0")/../migrations/V2__seed_reference_data.sql"

# -----------------------------------------------------------------------
# Row count validation
# -----------------------------------------------------------------------
echo "[INFO] Source row counts:"
$MYSQL -e "
SELECT table_name, table_rows
FROM information_schema.TABLES
WHERE table_schema = 'madmax'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;"

echo "[OK] Cloud SQL source seeding complete. Ready for DMS full-load."
