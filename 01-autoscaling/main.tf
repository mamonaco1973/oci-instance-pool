# ================================================================================
# Provider Configuration
# Auth is read from ~/.oci/config DEFAULT profile — no credentials in code
# ================================================================================

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "oci" {
  region = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment to deploy resources into"
}

# ================================================================================
# SSH Key Pair
# Generated fresh each deploy — private key written to keys/ (gitignored).
# ECDSA P-256 is smaller and faster than RSA while being equally secure.
# ================================================================================

resource "tls_private_key" "ssh" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "./keys/Private_Key"
  file_permission = "0600"
}

# ================================================================================
# Availability Domains
# OCI requires explicit AD selection for instance pool placement — resolved
# dynamically so this works across regions with different AD counts.
# ================================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# ================================================================================
# Image Lookup
# Queries OCI for the latest Ubuntu 24.04 image compatible with
# VM.Standard.E4.Flex, eliminating the need to hard-code an image OCID.
# sort_order = DESC + most_recent equivalent returns the newest matching image.
# ================================================================================

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}
