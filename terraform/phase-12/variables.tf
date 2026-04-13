# Phase 12.1: Terraform Configuration Variables
# Default values and required variable definitions

variable "vpc_id_us_west" {
  type        = string
  description = "VPC ID for US West region"
  validation {
    condition     = can(regex("^vpc-", var.vpc_id_us_west))
    error_message = "VPC ID must start with 'vpc-'"
  }
}

variable "vpc_id_eu_west" {
  type        = string
  description = "VPC ID for EU West region"
  validation {
    condition     = can(regex("^vpc-", var.vpc_id_eu_west))
    error_message = "VPC ID must start with 'vpc-'"
  }
}

variable "vpc_id_ap_south" {
  type        = string
  description = "VPC ID for AP South region"
  validation {
    condition     = can(regex("^vpc-", var.vpc_id_ap_south))
    error_message = "VPC ID must start with 'vpc-'"
  }
}

variable "route_table_id_us_west" {
  type        = string
  description = "Route table ID for US West region"
  validation {
    condition     = can(regex("^rtb-", var.route_table_id_us_west))
    error_message = "Route table ID must start with 'rtb-'"
  }
}

variable "route_table_id_eu_west" {
  type        = string
  description = "Route table ID for EU West region"
  validation {
    condition     = can(regex("^rtb-", var.route_table_id_eu_west))
    error_message = "Route table ID must start with 'rtb-'"
  }
}

variable "route_table_id_ap_south" {
  type        = string
  description = "Route table ID for AP South region"
  validation {
    condition     = can(regex("^rtb-", var.route_table_id_ap_south))
    error_message = "Route table ID must start with 'rtb-'"
  }
}

variable "nacl_id_us_west" {
  type        = string
  description = "Network ACL ID for US West region"
  validation {
    condition     = can(regex("^acl-", var.nacl_id_us_west))
    error_message = "Network ACL ID must start with 'acl-'"
  }
}

variable "nacl_id_eu_west" {
  type        = string
  description = "Network ACL ID for EU West region"
  validation {
    condition     = can(regex("^acl-", var.nacl_id_eu_west))
    error_message = "Network ACL ID must start with 'acl-'"
  }
}

variable "nacl_id_ap_south" {
  type        = string
  description = "Network ACL ID for AP South region"
  validation {
    condition     = can(regex("^acl-", var.nacl_id_ap_south))
    error_message = "Network ACL ID must start with 'acl-'"
  }
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production"
  }
}

variable "project_name" {
  type        = string
  description = "Project name for tagging"
  default     = "multi-region-federation"
}

variable "enable_dns_failover" {
  type        = bool
  description = "Enable Route53 geo-DNS failover"
  default     = true
}

variable "enable_cross_region_replication" {
  type        = bool
  description = "Enable cross-region data replication"
  default     = true
}

variable "monitoring_email" {
  type        = string
  description = "Email for failover alerts"
  default     = "ops@example.com"
}

variable "tags" {
  type = object({
    Terraform   = bool
    Phase       = string
    Environment = string
    CostCenter  = string
  })
  description = "Common tags applied to all resources"
  default = {
    Terraform   = true
    Phase       = "12"
    Environment = "production"
    CostCenter  = "engineering"
  }
}
