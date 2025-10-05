output "self_link" {
  value = google_compute_network.vpc.self_link
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "subnets" {
  value = google_compute_subnetwork.subnets[*]
}

