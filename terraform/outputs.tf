output "source_db_ip" {
  value = module.source_db.public_ip_address
}

output "destination_db_ip" {
  value = module.destination_db.endpoint
}