output "lb_public_ip" {
  description = "Load balancer public IP — open in browser to see the welcome page"
  value       = oci_load_balancer_load_balancer.main.ip_address_details[0].ip_address
}

output "lb_ocid" {
  description = "Load balancer OCID — used by validate.sh to check backend health"
  value       = oci_load_balancer_load_balancer.main.id
}
