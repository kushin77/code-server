terraform {
  required_version = ">= 1.7.0"
}

locals {
  module_labels = merge(
    var.labels,
    {
      module = var.module_name
    }
  )
}

# Add module resources below.
# Keep resource names deterministic and inputs explicit.