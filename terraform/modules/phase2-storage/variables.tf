variable "prometheus_storage_size" {
  type        = number
  description = "Prometheus storage size in Gi"
  default     = 50
}

variable "loki_storage_size" {
  type        = number
  description = "Loki storage size in Gi"
  default     = 20
}

variable "code_server_workspace_size" {
  type        = number
  description = "code-server workspace size in Gi"
  default     = 100
}

variable "velero_storage_size" {
  type        = number
  description = "Velero backup storage size in Gi"
  default     = 500
}

variable "create_prometheus_pv" {
  type        = bool
  description = "Create Prometheus PV"
  default     = true
}

variable "create_loki_pv" {
  type        = bool
  description = "Create Loki PV"
  default     = true
}

variable "create_code_server_workspace_pv" {
  type        = bool
  description = "Create code-server workspace PV"
  default     = true
}

variable "create_velero_pv" {
  type        = bool
  description = "Create Velero backup PV"
  default     = true
}
