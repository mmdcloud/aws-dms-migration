variable "allocated_storage" {}
variable "apply_immediately" {}
variable "engine_version" {}
variable "replication_instance_class" {}
variable "replication_instance_id" {}
variable "vpc_security_group_ids" {}

variable "source_endpoint_id" {}
variable "source_endpoint_type" {}
variable "source_engine_name" {}
variable "source_username" {}
variable "source_password" {}
variable "source_server_name" {}
variable "source_port" {}

variable "source_ssl_mode" {
  type        = string
  description = "SSL mode for the source endpoint"
  default     = "none"
  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.source_ssl_mode)
    error_message = "ssl_mode must be one of: none, require, verify-ca, verify-full"
  }
}

variable "source_certificate_arn" {
  type        = string
  description = "ARN of the DMS certificate for the source endpoint"
  default     = null
}

variable "destination_ssl_mode" {
  type        = string
  description = "SSL mode for the destination endpoint"
  default     = "none"
  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.destination_ssl_mode)
    error_message = "ssl_mode must be one of: none, require, verify-ca, verify-full"
  }
}

variable "destination_certificate_arn" {
  type        = string
  description = "ARN of the DMS certificate for the destination endpoint"
  default     = null
}


variable "destination_endpoint_id" {}
variable "destination_endpoint_type" {}
variable "destination_engine_name" {}
variable "destination_username" {}
variable "destination_password" {}
variable "destination_server_name" {}
variable "destination_port" {}
variable "publicly_accessible" {
  type        = bool
  description = "Whether the DMS replication instance is publicly accessible"
}
variable "subnet_group_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DMS replication subnet group"
}

variable "replication_subnet_group_id" {
  description = "ID of the DMS replication subnet group"
  type        = string
}
variable "replication_subnet_group_description" {
  description = "Description of the DMS replication subnet group"
  type        = string
}

variable "tasks" {

}