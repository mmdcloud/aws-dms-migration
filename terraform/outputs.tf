output "source_db_ip" {
  value = module.source_db.public_ip_address
}

output "destination_db_ip" {
  value = module.destination_db.endpoint
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = module.source_db.private_ip_address
}

output "cloud_sql_ip_range" {
  description = "Cloud SQL peered IP range"
  value       = google_compute_global_address.source_sql_private_ip_address.address
}