variable "serverless_vpc_connectors" {
  type = list(object({
    name = string
    ip_cidr_range = string
    min_instances = string
    max_instances = string
    machine_type = string
  }))
}
variable "vpc_name" {}