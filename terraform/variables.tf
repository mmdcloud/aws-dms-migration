variable "source_location" {
  type = string
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.source_location))
    error_message = "Must be a valid GCP region (e.g., us-central1)."
  }
}

variable "destination_location" {
  type = string
  validation {
    condition     = can(regex("^(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]$", var.destination_location))
    error_message = "Must be a valid AWS region (e.g., us-east-1, eu-west-2)."
  }
}

variable "gcp_project" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project))
    error_message = "Must be a valid GCP project ID (lowercase letters, digits, hyphens; 6-30 chars)."
  }
}

variable "source_db" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.source_db))
    error_message = "Database name must start with a letter and contain only letters, digits, or underscores (max 64 chars)."
  }
}

variable "destination_db" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.destination_db))
    error_message = "Database name must start with a letter and contain only letters, digits, or underscores (max 64 chars)."
  }
}

variable "destination_public_subnets" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  validation {
    condition     = alltrue([for s in var.destination_public_subnets : can(cidrnetmask(s))])
    error_message = "All public subnet values must be valid CIDR blocks (e.g., 10.0.1.0/24)."
  }
}

variable "destination_private_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  validation {
    condition     = alltrue([for s in var.destination_private_subnets : can(cidrnetmask(s))])
    error_message = "All private subnet values must be valid CIDR blocks (e.g., 10.0.4.0/24)."
  }
}

variable "destination_database_subnets" {
  type        = list(string)
  description = "Database Subnet CIDR values"
  validation {
    condition     = alltrue([for s in var.destination_database_subnets : can(cidrnetmask(s))])
    error_message = "All database subnet values must be valid CIDR blocks (e.g., 10.0.7.0/24)."
  }
}

variable "destination_azs" {
  type        = list(string)
  description = "Availability Zones"
  validation {
    condition     = length(var.destination_azs) >= 2 && alltrue([for az in var.destination_azs : can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", az))])
    error_message = "Must provide at least 2 valid AWS AZs (e.g., us-east-1a)."
  }
}

variable "notification_email" {
  type        = string
  description = "Notification Email"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "dms_engine_version" {
  type        = string
  description = "DMS Engine Version"
  validation {
    condition     = can(regex("^3\\.(5|6)\\.[0-9]+$", var.dms_engine_version))
    error_message = "DMS engine version must be 3.5.x or 3.6.x (e.g., 3.6.1)."
  }
}