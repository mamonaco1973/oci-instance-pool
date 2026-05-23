# ================================================================================
# Instance Configuration
# Defines the blueprint for every instance the pool creates. When the pool
# scales out it launches new instances from this configuration. Changes here
# (new image, updated user_data) take effect on the next scale-out — existing
# instances are not replaced until they are cycled by the pool.
# ================================================================================

resource "oci_core_instance_configuration" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "asg-instance-config"

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      display_name   = "asg-instance"
      shape          = "VM.Standard.A1.Flex"

      # Ampere ARM at ~$0.01/OCPU/hr — still cheaper than E4.Flex at $0.025.
      # 1 GB OOMs during dnf on Oracle Linux 9; 4 GB is the comfortable floor.
      shape_config {
        ocpus         = 1
        memory_in_gbs = 4
      }

      source_details {
        source_type = "image"
        image_id    = data.oci_core_images.oracle_linux.images[0].id
      }

      create_vnic_details {
        subnet_id = oci_core_subnet.private.id
        # Instances live in the private subnet and must not receive public IPs —
        # all inbound traffic arrives through the load balancer, never directly
        assign_public_ip = false
      }

      metadata = {
        ssh_authorized_keys = tls_private_key.ssh.public_key_openssh
        # user_data must be base64-encoded — cloud-init decodes it on first boot
        user_data = base64encode(file("${path.module}/scripts/userdata.sh"))
      }
    }
  }
}
