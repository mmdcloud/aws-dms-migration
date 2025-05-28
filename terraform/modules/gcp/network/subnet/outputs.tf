output "subnets"{
    value = google_compute_subnetwork.subnet[*]
}