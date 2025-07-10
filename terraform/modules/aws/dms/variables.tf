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
variable "source_ssl_mode" {}

variable "destination_endpoint_id" {}
variable "destination_endpoint_type" {}
variable "destination_engine_name" {}
variable "destination_username" {}
variable "destination_password" {}
variable "destination_server_name" {}
variable "destination_port" {}
variable "destination_ssl_mode" {}
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