# ================================================================================
# Load Balancer
# The LB is the single public entry point for the application. It distributes
# incoming HTTP requests across healthy instances in both ADs, performs health
# checks to detect failed instances, and removes them from rotation
# automatically. Clients always talk to the LB — never directly to instances.
# ================================================================================

resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "asg-lb"

  # Flexible shape allows bandwidth to scale with traffic — minimum 10 Mbps
  # prevents cost at idle, maximum 100 Mbps caps spend for this demo
  shape = "flexible"
  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 100
  }

  # is_private = false gives the LB a public IP so it is reachable from
  # the internet — placed in the public subnet
  is_private = false
  subnet_ids = [oci_core_subnet.public.id]

  freeform_tags = { "Name" = "asg-lb" }
}

# The backend set is the pool of instances the LB routes traffic to.
# The instance pool registers and deregisters backends here as it scales.
resource "oci_load_balancer_backend_set" "main" {
  name             = "asg-backend-set"
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol = "HTTP"
    url_path = "/"
    port     = 80

    # Check every 10 seconds — fast enough to detect failures within a minute
    interval_ms = 10000

    # Require 3 consecutive successes before marking healthy, preventing a
    # slow-starting instance from receiving traffic before apache2 is ready
    retries = 3

    # 3-second timeout per attempt — generous enough for a loaded instance
    # but short enough to detect a hung instance within one interval
    return_code       = 200
    timeout_in_millis = 3000
  }
}

# The listener watches port 80 and forwards all requests to the backend set.
resource "oci_load_balancer_listener" "http" {
  name                     = "asg-listener"
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  default_backend_set_name = oci_load_balancer_backend_set.main.name
  port                     = 80
  protocol                 = "HTTP"
}
