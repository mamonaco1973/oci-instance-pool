# ================================================================================
# Networking
# Two-tier network: public subnet hosts the load balancer; private subnet hosts
# instances. Instances reach the internet through a NAT gateway and are never
# directly reachable from outside the VCN.
#
# CIDR layout — 10.0.0.0/24 split into two /26 blocks:
#   10.0.0.0/26   — public  (load balancer)
#   10.0.0.128/26 — private (instances)
#
# Both subnets are regional (no availability_domain set), so the load balancer
# and instance pool can span all three ADs in us-ashburn-1.
# ================================================================================

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/24"
  display_name   = "asg-vcn"
  # dns_label must be alphanumeric and ≤ 15 chars — forms the VCN's DNS domain
  dns_label = "asgvcn"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "asg-igw"
  enabled        = true
}

# NAT gateway provides egress-only internet access for private instances —
# inbound connections cannot be initiated through it from outside
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "asg-nat"
  # block_traffic = false lets private instances initiate outbound connections
  block_traffic = false
}

# ================================================================================
# Public Route Table
# Routes all internet-bound traffic through the IGW — attached to the public
# subnet so the load balancer can be reached from the internet.
# ================================================================================

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "asg-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# ================================================================================
# Private Route Table
# Routes all internet-bound traffic through the NAT gateway — used by private
# instances for package installation and OCI API calls outbound only.
# ================================================================================

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "asg-private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }
}

# ================================================================================
# Public Subnet
# Hosts the load balancer. Regional (no availability_domain set) so the LB
# can operate across all ADs. Security list allows port 80 from the internet.
# ================================================================================

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.0.0/26"
  display_name      = "asg-public-subnet"
  dns_label         = "asgpub"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]

  # LB nodes need public IPs to be internet-facing — private subnet does not
  prohibit_public_ip_on_vnic = false
}

# ================================================================================
# Private Subnet
# Instances live here. No public IPs are assigned — all inbound traffic arrives
# through the load balancer, and all outbound traffic exits through the NAT
# gateway. Instances are unreachable from the internet by design.
# ================================================================================

resource "oci_core_subnet" "private" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.0.128/26"
  display_name      = "asg-private-subnet"
  dns_label         = "asgpriv"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private.id]

  # Explicitly prohibit public IPs — instances must never receive one
  prohibit_public_ip_on_vnic = true
}
