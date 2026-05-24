# ------------------------------------------------------------------------
# GCP Secret(Vault) Configuration
# ------------------------------------------------------------------------
data "vault_generic_secret" "cloudsql" {
  path = "secret/sql"
}

# ------------------------------------------------------------------------
# GCP Secret Manager Configuration
# ------------------------------------------------------------------------
module "source_cloudsql_password_secret" {
  source      = "./modules/gcp/secret-manager"
  secret_id   = "source_db_password_secret"
  secret_data = tostring(data.vault_generic_secret.cloudsql.data["password"])
}

# ------------------------------------------------------------------------
# AWS Secret(Vault) Configuration
# ------------------------------------------------------------------------
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

# ------------------------------------------------------------------------
# AWS Secret Manager Configuration
# ------------------------------------------------------------------------
module "destination_db_credentials" {
  source                  = "./modules/aws/secrets-manager"
  name                    = "destination-rds-secrets-${random_id.id.hex}"
  description             = "destination_rds_secrets"
  recovery_window_in_days = 30
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
}