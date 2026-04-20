# Flyway Schema Migration — GCP Cloud SQL → AWS RDS

## Architecture Context

```
Cloud SQL MySQL 8.0          AWS DMS (3.6.1)          RDS MySQL 8.0
  madmax DB           ──────────────────────►   destinationdb
  us-central1                                      us-east-1
  10.1.0.0/16          (HA VPN + BGP tunnel)    10.0.7-9.0/24 (DB subnets)
```

**DMS handles data replication. Flyway owns schema DDL, indexes, views, procedures, and post-migration evolution.** They are complementary tools, not alternatives.

---

## Flyway Features Used

| Feature | File | When it runs |
|---|---|---|
| **Versioned migration** | `V1__baseline_schema.sql` | Once — schema creation |
| **Versioned migration (DML)** | `V2__seed_reference_data.sql` | Once — reference/lookup data |
| **Versioned migration (DDL)** | `V3__post_migration_indexes.sql` | Once — after DMS full-load |
| **Schema evolution** | `V4__add_audit_and_discounts.sql` | Once — post-cutover additions |
| **Views + Procedures** | `V5__views_and_procedures.sql` | Once — objects DMS can't replicate |
| **Repeatable migration** | `R__reporting_views.sql` | On every checksum change |
| **beforeMigrate callback** | `callbacks/beforeMigrate__safety_checks.sql` | Before every `flyway migrate` |
| **afterMigrate callback** | `callbacks/afterMigrate__validation.sql` | After every successful migrate |
| **`flyway.conf`** | `conf/flyway.conf` | Config: cleanDisabled, validateOnMigrate, baselineOnMigrate |
| **CI/CD pipeline** | `scripts/flyway-migrate.yml` | PR validate → main migrate |
| **Docker runner** | `docker/docker-compose.yml` | Local dev + CI container |

---

## Migration Order & DMS Integration

```
Phase 0: Pre-DMS
  └── flyway migrate (runs V1, V2)
      V1: Create all 8 tables on RDS target
      V2: Seed lookup data (regions, categories, warehouses, products, customers, orders)
      ↕ beforeMigrate/afterMigrate callbacks fire automatically

Phase 1: DMS Full-Load
  └── DMS replication task starts
      → Copies all rows from Cloud SQL (madmax) → RDS (destinationdb)
      → DMS ignores tables it finds empty; Flyway-seeded rows get overwritten by ON DUPLICATE KEY

Phase 2: DMS CDC (ongoing replication)
  └── DMS streams binlog changes from Cloud SQL
      → binlog_format = ROW confirmed in seed_cloudsql.sh
      → BGP route advertises 10.2.0.0/20 (Cloud SQL private range) over VPN

Phase 3: Post Full-Load (DMS still running CDC)
  └── flyway migrate (runs V3)
      V3: Re-add secondary indexes dropped pre-full-load for performance

Phase 4: Cutover (stop DMS, switch app to RDS)
  └── validate_migration.sh: compare row counts source vs target
  └── flyway migrate (runs V4, V5, R__)
      V4: Add audit columns + discount_codes table (RDS-only features)
      V5: Create views + stored procedures (DMS cannot replicate these)
      R__: Reporting views (re-runs whenever file changes)
```

---

## Directory Structure

```
flyway-migration/
├── migrations/
│   ├── V1__baseline_schema.sql       # 8 tables: regions, categories, customers,
│   │                                  #   products, warehouses, inventory,
│   │                                  #   orders, order_items
│   ├── V2__seed_reference_data.sql   # Lookup + sample transactional data
│   ├── V3__post_migration_indexes.sql # Composite indexes added post-full-load
│   ├── V4__add_audit_and_discounts.sql # Schema evolution + new table
│   ├── V5__views_and_procedures.sql  # Views, SPs — DMS can't replicate these
│   └── R__reporting_views.sql        # Repeatable — re-runs on content change
├── callbacks/
│   ├── beforeMigrate__safety_checks.sql
│   └── afterMigrate__validation.sql
├── conf/
│   └── flyway.conf                   # cleanDisabled=true, baselineOnMigrate config
├── docker/
│   └── docker-compose.yml            # Local MySQL 8.0 + Flyway runner
└── scripts/
    ├── run_flyway.sh                 # Pulls creds from AWS Secrets Manager
    ├── seed_cloudsql.sh              # Seeds Cloud SQL source before DMS
    ├── validate_migration.sh         # Row count diff: Cloud SQL vs RDS
    └── flyway-migrate.yml            # GitHub Actions CI/CD pipeline
```

---

## Schema: 8 Tables

```
regions ──────────────────────────────────────────────────────┐
   ↑                                                           │
categories (self-ref tree)                                     │
   ↑                                                           ↓
products ──────────────────────── inventory ──── warehouses ◄──┘
   ↑                                    ↑              ↑
order_items ◄──── orders ───────────────────────────────┘
                    ↑
                customers ◄──── regions
```

| Table | Rows seeded | Notes |
|---|---|---|
| `regions` | 8 | Lookup — not DMS-replicated |
| `categories` | 10 (3 levels) | Self-referencing tree |
| `customers` | 30 | Multi-region, multi-tier |
| `products` | 20 | SKUs across 5 categories |
| `warehouses` | 5 | US/EU/APAC |
| `inventory` | 42 | product × warehouse with reorder tracking |
| `orders` | 10 | Multi-status, multi-currency |
| `order_items` | 13 | Order lines with qty + line_total |

---

## Quick Start

```bash
# 1. Local dev: spin up MySQL + run all migrations
cd docker && docker compose up mysql -d
docker compose run --rm flyway migrate

# 2. Check migration status
docker compose run --rm flyway info

# 3. Against real RDS (set env vars first)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export RDS_SECRET_NAME="destination-rds-secrets-<random_id>"
./scripts/run_flyway.sh migrate

# 4. Validate row counts between Cloud SQL and RDS
export CLOUD_SQL_HOST=<private-ip>
export CLOUD_SQL_USER=<user>
export CLOUD_SQL_PASS=<pass>
./scripts/validate_migration.sh
```

---

## Key `flyway.conf` Safety Settings

```properties
flyway.cleanDisabled=true          # Never drop all tables in production
flyway.validateOnMigrate=true      # Checksum validate before applying
flyway.outOfOrderMigration=false   # Strict V1 → V2 → V3 ordering
flyway.baselineOnMigrate=false     # Set true only on first-time Flyway adoption
                                   # if DMS already loaded data before Flyway ran
```

---

## Interview Talking Points

- **Flyway vs DMS separation of concerns**: DMS moves bytes; Flyway owns DDL lifecycle.
- **`baselineOnMigrate`**: Critical if DMS runs first and you adopt Flyway mid-migration — stamps existing schema as V1 without re-running DDL.
- **Index strategy**: Drop secondary indexes on RDS before DMS full-load → bulk insert speed; V3 re-adds them after. Real production decision, not boilerplate.
- **`R__` repeatable migrations**: Views evolve without version bumps; Flyway detects checksum change and re-runs automatically.
- **Callbacks**: `beforeMigrate` acts as a circuit-breaker; `afterMigrate` builds an audit log — both visible in `flyway_schema_history` table.
- **`cleanDisabled=true`**: Non-negotiable on production; prevents accidental `flyway clean` wiping the database.
