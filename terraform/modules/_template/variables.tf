variable "module_name" {
  description = "Short name for the module used in labels and documentation."
  type        = string
}

variable "labels" {
  description = "Shared labels or tags merged into all module resources."
  type        = map(string)
  default     = {}
}