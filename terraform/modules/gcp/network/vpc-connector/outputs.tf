output "vpc_connectors" {
  value = google_vpc_access_connector.connector[*]
}