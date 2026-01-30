# 🚀 Cross-Cloud Database Migration: GCP Cloud SQL to AWS RDS

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4?style=for-the-badge&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-DMS-FF9900?style=for-the-badge&logo=amazon-aws)](https://aws.amazon.com/dms/)
[![GCP](https://img.shields.io/badge/GCP-Cloud%20SQL-4285F4?style=for-the-badge&logo=google-cloud)](https://cloud.google.com/sql)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://www.mysql.com/)

A production-ready, enterprise-grade Terraform infrastructure for seamless MySQL database migration from Google Cloud Platform (Cloud SQL) to Amazon Web Services (RDS) using AWS Database Migration Service with High Availability VPN connectivity and real-time Change Data Capture (CDC).

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Key Features](#-key-features)
- [Prerequisites](#-prerequisites)
- [Network Architecture](#-network-architecture)
- [Components](#-components)
- [Quick Start](#-quick-start)
- [Configuration](#%EF%B8%8F-configuration)
- [Deployment Guide](#-deployment-guide)
- [Monitoring & Alerts](#-monitoring--alerts)
- [Validation & Testing](#-validation--testing)
- [Troubleshooting](#-troubleshooting)
- [Security Best Practices](#-security-best-practices)
- [Cost Optimization](#-cost-optimization)
- [Migration Strategy](#-migration-strategy)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🏗️ Architecture Overview

![Architecture Diagram](./docs/architecture.svg)

### Architecture Highlights

This solution implements a **secure, highly-available cross-cloud database migration** architecture with the following design principles:

- **Zero Downtime Migration**: Full-load followed by continuous Change Data Capture (CDC)
- **High Availability**: 4 redundant IPSec VPN tunnels with BGP routing
- **Security First**: Private connectivity, no public endpoints, encrypted secrets
- **Production Ready**: Automated monitoring, alerting, and validation
- **Infrastructure as Code**: 100% Terraform-managed with modular design

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Initial Full Load → 2. Continuous CDC → 3. Real-time Sync          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Features

### 🔒 Security
- ✅ **Zero Public Endpoints** - All databases accessible only via private IPs
- ✅ **Encrypted Secrets** - HashiCorp Vault + AWS Secrets Manager + GCP Secret Manager
- ✅ **Network Isolation** - Security groups and firewall rules with least privilege
- ✅ **Binary Log Encryption** - Secure CDC replication

### 🌐 High Availability
- ✅ **4x Redundant VPN Tunnels** - GCP HA VPN + AWS VPN with BGP
- ✅ **Multi-AZ RDS** - Automatic failover protection
- ✅ **Regional Cloud SQL** - GCP regional high availability
- ✅ **Auto Route Failover** - BGP-based intelligent routing

### 📊 Monitoring & Observability
- ✅ **CloudWatch Alarms** - CPU, Memory, and DMS metrics
- ✅ **SNS Notifications** - Real-time email alerts
- ✅ **DMS Event Subscriptions** - Migration status tracking
- ✅ **VPN Health Checks** - Automated tunnel status validation

### 🚀 Migration Capabilities
- ✅ **Full Load + CDC** - Complete data migration with ongoing changes
- ✅ **Table Transformations** - Automatic schema prefix management
- ✅ **Large Object Support** - Optimized LOB handling
- ✅ **Parallel Processing** - Multi-threaded full load (8 subtasks)

---

## 📦 Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://www.terraform.io/downloads.html) | ≥ 1.0 | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | ≥ 2.0 | AWS resource management |
| [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) | Latest | GCP resource management |
| [Vault CLI](https://www.vaultproject.io/downloads) | ≥ 1.8 | Secret management |

### Cloud Provider Accounts

- **AWS Account** with appropriate IAM permissions
- **GCP Project** with billing enabled
- **HashiCorp Vault** instance (or alternative secret store)

### Required Permissions

<details>
<summary>AWS IAM Permissions (Click to expand)</summary>

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "dms:*",
        "secretsmanager:*",
        "sns:*",
        "cloudwatch:*",
        "iam:CreateRole",
        "iam:AttachRolePolicy"
      ],
      "Resource": "*"
    }
  ]
}
```
</details>

<details>
<summary>GCP IAM Roles (Click to expand)</summary>

- `roles/compute.networkAdmin`
- `roles/cloudsql.admin`
- `roles/secretmanager.admin`
- `roles/iam.serviceAccountUser`
</details>

---

## 🌐 Network Architecture

### IP Address Space

| Network | CIDR Block | Purpose |
|---------|------------|---------|
| **GCP VPC** | `10.1.0.0/16` | Source Cloud SQL network |
| **Cloud SQL Peering** | `10.2.0.0/20` | Private IP for Cloud SQL |
| **AWS VPC** | `10.0.0.0/16` | Destination RDS network |

### VPN Topology

```
GCP HA VPN Gateway              AWS Virtual Private Gateway
┌─────────────────┐            ┌─────────────────┐
│  Interface 0    │────────────│   Tunnel 1      │
│                 │────────────│   Tunnel 2      │
│                 │            │                 │
│  Interface 1    │────────────│   Tunnel 3      │
│                 │────────────│   Tunnel 4      │
└─────────────────┘            └─────────────────┘
   ASN: 65000                     ASN: 65001
```

### BGP Configuration

- **GCP Router ASN**: 65000
- **AWS VGW ASN**: 65001
- **Advertised Routes**: `10.1.0.0/16`, `10.2.0.0/20`
- **Route Priority**: 100
- **BGP Sessions**: 4 (one per tunnel)

---

## 🧩 Components

### Google Cloud Platform

| Component | Type | Configuration |
|-----------|------|---------------|
| **Cloud SQL** | MySQL 8.0 | Regional HA, Binary logs enabled |
| **VPC** | Custom | `10.1.0.0/16` with private Google access |
| **HA VPN Gateway** | Site-to-site | 2 interfaces, 99.99% SLA |
| **Cloud Router** | BGP | Custom route advertisement |
| **Firewall Rules** | Ingress/Egress | Port 3306 from AWS CIDR |

### Amazon Web Services

| Component | Type | Configuration |
|-----------|------|---------------|
| **RDS MySQL** | db.t3.micro | Multi-AZ, automated backups |
| **VPC** | Custom | 3 AZs with public/private/database subnets |
| **VPN Gateway** | Site-to-site | Attached to VPC with BGP |
| **DMS Instance** | dms.t3.medium | 20GB storage, private subnet |
| **Security Groups** | Network | Least privilege access control |
| **CloudWatch** | Monitoring | CPU, memory, and custom metrics |
| **SNS** | Notifications | Email alerts for events |

### Secret Management

| Provider | Secret Type | Purpose |
|----------|-------------|---------|
| **HashiCorp Vault** | Primary Store | Source of truth for credentials |
| **GCP Secret Manager** | Regional | Cloud SQL password |
| **AWS Secrets Manager** | Regional | RDS credentials |

---

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/gcp-to-aws-db-migration.git
cd gcp-to-aws-db-migration
```

### 2. Configure Vault Secrets

```bash
# Set Cloud SQL credentials
vault kv put secret/sql username=mohit password=your-secure-password

# Set RDS credentials
vault kv put secret/rds username=admin password=your-secure-password
```

### 3. Configure Variables

Create `terraform.tfvars`:

```hcl
# GCP Configuration
source_location = "us-central1"
source_db       = "source_database"

# AWS Configuration
destination_azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
destination_public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
destination_private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
destination_database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
destination_db               = "destination_database"
```

### 4. Initialize & Deploy

```bash
# Initialize Terraform
terraform init

# Review execution plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 5. Verify Deployment

```bash
# Check VPN tunnel status
./scripts/check_vpn_status.sh

# Validate DMS endpoints
./scripts/validate_dms.sh
```

---

## ⚙️ Configuration

### Environment Variables

```bash
# AWS Configuration
export AWS_REGION=us-east-1
export AWS_PROFILE=your-profile

# GCP Configuration
export GOOGLE_PROJECT=your-project-id
export GOOGLE_REGION=us-central1

# Vault Configuration
export VAULT_ADDR=https://vault.example.com
export VAULT_TOKEN=your-token
```

### Terraform Variables

<details>
<summary>Complete Variable Reference (Click to expand)</summary>

```hcl
variable "source_location" {
  description = "GCP region for Cloud SQL"
  type        = string
  default     = "us-central1"
}

variable "source_db" {
  description = "Source database name"
  type        = string
}

variable "destination_azs" {
  description = "AWS availability zones"
  type        = list(string)
}

variable "destination_public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "destination_private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "destination_database_subnets" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
}

variable "destination_db" {
  description = "Destination database name"
  type        = string
}
```
</details>

### DMS Task Configuration

The DMS task is configured for optimal performance:

```json
{
  "TargetMetadata": {
    "SupportLobs": true,
    "LimitedSizeLobMode": true,
    "LobMaxSize": 32
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE",
    "MaxFullLoadSubTasks": 8
  }
}
```

---

## 📚 Deployment Guide

### Phase 1: Network Setup (10-15 minutes)

```bash
# Deploy VPCs and networking
terraform apply -target=module.source_vpc
terraform apply -target=module.destination_vpc
```

### Phase 2: VPN Establishment (15-20 minutes)

```bash
# Deploy VPN infrastructure
terraform apply -target=google_compute_ha_vpn_gateway.gcp_vpn_gateway
terraform apply -target=aws_vpn_gateway.aws_vpn_gw

# Wait for BGP convergence
sleep 300
```

**Validation Checkpoint**: Verify all 4 VPN tunnels are UP

```bash
aws ec2 describe-vpn-connections \
  --query 'VpnConnections[*].VgwTelemetry[*].[OutsideIpAddress,Status]' \
  --output table
```

### Phase 3: Database Setup (20-30 minutes)

```bash
# Deploy databases
terraform apply -target=module.source_db
terraform apply -target=module.destination_db

# Verify connectivity
mysql -h <cloud-sql-private-ip> -u mohit -p
mysql -h <rds-endpoint> -u admin -p
```

### Phase 4: DMS Configuration (10-15 minutes)

```bash
# Deploy DMS infrastructure
terraform apply -target=module.dms_replication_instance

# Start migration task (automatic with full apply)
terraform apply
```

### Phase 5: Monitoring Setup (5 minutes)

```bash
# Deploy CloudWatch alarms and SNS
terraform apply -target=module.dms_cpu
terraform apply -target=module.dms_freeable_memory
terraform apply -target=module.dms_event_notification
```

---

## 📊 Monitoring & Alerts

### CloudWatch Metrics

| Metric | Threshold | Action |
|--------|-----------|--------|
| **CPU Utilization** | > 80% | SNS Alert |
| **Freeable Memory** | < 500MB | SNS Alert |
| **Network Throughput** | Monitored | CloudWatch Dashboard |
| **Replication Lag** | > 60s | Investigation |

### DMS Event Subscriptions

Automated notifications for:
- ✅ Replication instance creation/deletion
- ✅ Task failures
- ✅ Configuration changes
- ✅ Endpoint connection issues

### Accessing Logs

```bash
# DMS CloudWatch logs
aws logs tail /aws/dms/tasks/cloudsql-to-rds-task --follow

# VPN tunnel status
gcloud compute routers get-status gcp-vpn-router \
  --region=us-central1
```

---

## ✅ Validation & Testing

### Automated Validation Script

The deployment includes automatic VPN validation:

```bash
# Checks performed:
# 1. VPN tunnel status (all 4 tunnels)
# 2. BGP session establishment
# 3. Route propagation
# 4. Network connectivity
```

### Manual Testing

```bash
# Test source connectivity from AWS
aws ec2 run-instances \
  --image-id ami-xxxxx \
  --instance-type t2.micro \
  --subnet-id subnet-xxxxx \
  --user-data '#!/bin/bash
    mysql -h <cloud-sql-ip> -u mohit -p<password> -e "SHOW DATABASES;"
  '

# Verify DMS task status
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=cloudsql-to-rds-task"
```

### Data Validation

```sql
-- Compare record counts
-- Source (Cloud SQL)
SELECT TABLE_NAME, TABLE_ROWS 
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = 'source_database';

-- Target (RDS)
SELECT TABLE_NAME, TABLE_ROWS 
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = 'destination_database';
```

---

## 🔧 Troubleshooting

### Common Issues

<details>
<summary><b>VPN Tunnels Not Establishing</b></summary>

**Symptoms**: Tunnel status shows "DOWN"

**Solutions**:
1. Verify BGP ASN configuration matches
2. Check firewall rules allow UDP 500, 4500
3. Validate pre-shared keys
4. Review CloudWatch logs for IKE errors

```bash
# Check tunnel details
aws ec2 describe-vpn-connections --vpn-connection-ids vpn-xxxxx
```
</details>

<details>
<summary><b>DMS Task Fails to Start</b></summary>

**Symptoms**: Task shows "failed" status

**Solutions**:
1. Verify endpoint connectivity
2. Check security group rules
3. Validate credentials in Vault
4. Review DMS logs in CloudWatch

```bash
# Test endpoint connection
aws dms test-connection \
  --replication-instance-arn arn:aws:dms:... \
  --endpoint-arn arn:aws:dms:...
```
</details>

<details>
<summary><b>High Replication Lag</b></summary>

**Symptoms**: CDCLatencySource > 60 seconds

**Solutions**:
1. Increase DMS instance size
2. Optimize table indexes
3. Check network throughput
4. Review binary log size

```bash
# Monitor CDC metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DMS \
  --metric-name CDCLatencySource \
  --dimensions Name=ReplicationInstanceIdentifier,Value=dms-instance
```
</details>

### Debug Mode

Enable detailed logging:

```hcl
# In DMS task settings
Logging = {
  EnableLogging = true
  LogComponents = [
    {
      Id       = "SOURCE_CAPTURE"
      Severity = "LOGGER_SEVERITY_DEBUG"
    }
  ]
}
```

---

## 🔒 Security Best Practices

### Network Security

- ✅ **No Public IPs**: All database instances use private IPs only
- ✅ **Security Groups**: Least privilege access with specific CIDR ranges
- ✅ **Firewall Rules**: Stateful inspection on both clouds
- ✅ **VPN Encryption**: IPSec with AES-256 encryption

### Credential Management

```bash
# Rotate secrets regularly
vault kv put secret/sql password=$(openssl rand -base64 32)

# Enable secret versioning
vault secrets enable -version=2 -path=secret kv
```

### IAM Best Practices

- Use service accounts with minimal permissions
- Enable MFA for human access
- Rotate access keys every 90 days
- Audit IAM policies quarterly

### Compliance

- **Encryption at Rest**: Both Cloud SQL and RDS use encrypted storage
- **Encryption in Transit**: VPN tunnels + TLS for database connections
- **Audit Logging**: CloudWatch Logs + GCP Cloud Logging enabled
- **Backup Retention**: 7-day automated backups

---

## 💰 Cost Optimization

### Estimated Monthly Costs

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| **GCP Cloud SQL** | db-f1-micro | $15-20 |
| **GCP HA VPN** | 2 tunnels | $73 |
| **AWS RDS** | db.t3.micro Multi-AZ | $30-40 |
| **AWS DMS** | dms.t3.medium | $140 |
| **AWS VPN** | 2 connections | $72 |
| **Data Transfer** | Variable | $20-100 |
| **Total** | | **~$350-445/month** |

### Cost Saving Tips

1. **Right-size instances** after migration completes
2. **Delete DMS resources** post-migration
3. **Use Reserved Instances** for long-term RDS
4. **Enable compression** for VPN data transfer
5. **Schedule development environment** shutdown

```bash
# Post-migration cleanup
terraform destroy -target=module.dms_replication_instance
terraform destroy -target=google_compute_ha_vpn_gateway.gcp_vpn_gateway
terraform destroy -target=aws_vpn_gateway.aws_vpn_gw
```

---

## 📋 Migration Strategy

### Pre-Migration Checklist

- [ ] Backup source database
- [ ] Document current schema and data size
- [ ] Test application compatibility with RDS
- [ ] Plan maintenance window
- [ ] Notify stakeholders
- [ ] Prepare rollback plan

### Migration Phases

**Phase 1: Preparation** (Day 1-2)
- Deploy infrastructure
- Validate connectivity
- Test credentials

**Phase 2: Initial Load** (Day 3-4)
- Start DMS full load
- Monitor progress
- Validate data integrity

**Phase 3: CDC Sync** (Day 5-7)
- Enable CDC replication
- Monitor replication lag
- Perform test cutover

**Phase 4: Cutover** (Day 8)
- Final data validation
- Update application connection strings
- Switch traffic to RDS
- Monitor application health

**Phase 5: Cleanup** (Day 9-10)
- Verify application stability
- Remove DMS resources (optional)
- Document lessons learned

### Rollback Procedure

```bash
# Revert application to Cloud SQL
kubectl set env deployment/app DB_HOST=<cloud-sql-ip>

# Or using Terraform
terraform apply -var="use_cloud_sql=true"
```

---

## 📁 Project Structure

```
.
├── main.tf                          # Main configuration
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── terraform.tfvars                 # Variable values (gitignored)
├── modules/
│   ├── aws/
│   │   ├── vpc/                    # AWS VPC module
│   │   ├── rds/                    # RDS module
│   │   ├── dms/                    # DMS module
│   │   ├── security-groups/        # Security group module
│   │   ├── secrets-manager/        # Secrets Manager module
│   │   ├── sns/                    # SNS module
│   │   └── cloudwatch/             # CloudWatch module
│   └── gcp/
│       ├── vpc/                    # GCP VPC module
│       ├── cloud-sql/              # Cloud SQL module
│       └── secret-manager/         # Secret Manager module
├── scripts/
│   ├── check_vpn_status.sh         # VPN validation script
│   ├── validate_dms.sh             # DMS validation script
│   └── data_validation.sql         # Data comparison queries
├── docs/
│   ├── architecture.svg            # Architecture diagram
│   └── runbook.md                  # Operational runbook
└── README.md                        # This file
```

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md).

### Development Setup

```bash
# Install pre-commit hooks
pre-commit install

# Run tests
terraform fmt -recursive
terraform validate
tflint
```

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- AWS Database Migration Service team
- Google Cloud SQL team
- HashiCorp Terraform community
- Contributors and maintainers

---

## 📞 Support

- **Documentation**: [Wiki](https://github.com/yourusername/repo/wiki)
- **Issues**: [GitHub Issues](https://github.com/yourusername/repo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/repo/discussions)
- **Email**: support@example.com

---

## 🗺️ Roadmap

- [ ] Support for PostgreSQL migration
- [ ] Terraform Cloud integration
- [ ] Automated testing pipeline
- [ ] Multi-region disaster recovery
- [ ] Kubernetes operator for DMS tasks
- [ ] Cost optimization recommendations

---

<div align="center">

**⭐ Star this repo if you find it helpful!**

Made with ❤️ by [Your Team Name]

</div>
