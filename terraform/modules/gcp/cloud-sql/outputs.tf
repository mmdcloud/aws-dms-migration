output "db_user" {
  value = google_sql_user.db_user.name
}

output "db_password" {
  value = google_sql_user.db_user.password
}

output "db_ip_address" {
  value = google_sql_database_instance.db_instance.private_ip_address
}

output "db_name" {
  value = google_sql_database_instance.db_instance.name
}

output "db_connection_name" {
  value = google_sql_database_instance.db_instance.connection_name
}
