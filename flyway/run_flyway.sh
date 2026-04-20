#!/usr/bin/env bash
# =============================================================================
# run_flyway.sh
# Purpose: Pull RDS credentials from AWS Secrets Manager at runtime,
#          export as env vars, then invoke Flyway.
#          Never hardcodes credentials — integrates with your existing
#          Vault/Secrets Manager setup in main.tf.
#
# Usage:
#   ./scripts/run_flyway.sh migrate
#   ./scripts/run_flyway.sh info
#   ./scripts/run_flyway.sh validate
#   ./scripts/run_flyway.sh repair
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# -----------------------------------------------------------------------
# Config — adjust to match your Terraform outputs
# -----------------------------------------------------------------------
SECRET_NAME="${RDS_SECRET_NAME:-destination-rds-secrets}"   # Matches main.tf secrets-manager module
RDS_ENDPOINT="${RDS_ENDPOINT:-}"                             # Set externally or via terraform output
AWS_REGION="${AWS_REGION:-us-east-1}"                        # Matches destination_location in tfvars
FLYWAY_CMD="${1:-info}"                                      # Default: just show migration status

if [[ -z "$RDS_ENDPOINT" ]]; then
  echo "[ERROR] RDS_ENDPOINT is not set. Export it from Terraform output:"
  echo "  export RDS_ENDPOINT=\$(terraform output -raw rds_endpoint)"
  exit 1
fi

# -----------------------------------------------------------------------
# Pull credentials from AWS Secrets Manager
# (Secret created by module "destination_db_credentials" in main.tf)
# -----------------------------------------------------------------------
echo "[INFO] Fetching RDS credentials from Secrets Manager: $SECRET_NAME"
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

export FLYWAY_USER=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
export FLYWAY_PASSWORD=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
export RDS_ENDPOINT

# -----------------------------------------------------------------------
# Expand FLYWAY_URL with the resolved endpoint
# -----------------------------------------------------------------------
export FLYWAY_URL="jdbc:mysql://${RDS_ENDPOINT}:3306/destinationdb?useSSL=true&requireSSL=true&serverTimezone=UTC&allowPublicKeyRetrieval=false"

echo "[INFO] Connecting to: $RDS_ENDPOINT"
echo "[INFO] Running: flyway $FLYWAY_CMD"

# -----------------------------------------------------------------------
# Run Flyway
# -----------------------------------------------------------------------
flyway \
  -configFiles="${ROOT_DIR}/conf/flyway.conf" \
  -locations="filesystem:${ROOT_DIR}/migrations,filesystem:${ROOT_DIR}/callbacks" \
  "$FLYWAY_CMD"

echo "[INFO] Flyway $FLYWAY_CMD completed successfully"
