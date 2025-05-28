# Serverless VPC Connector
resource "google_vpc_access_connector" "connector" {
  count         = length(var.serverless_vpc_connectors)
  network       = var.vpc_name
  name          = var.serverless_vpc_connectors[count.index].name
  ip_cidr_range = var.serverless_vpc_connectors[count.index].ip_cidr_range
  min_instances = var.serverless_vpc_connectors[count.index].min_instances
  max_instances = var.serverless_vpc_connectors[count.index].max_instances
  machine_type  = var.serverless_vpc_connectors[count.index].machine_type
}