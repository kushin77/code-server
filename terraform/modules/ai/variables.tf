# @file terraform/modules/ai/variables.tf
# @description AI/ML infrastructure variables (Ollama, model routing)

variable "ollama_image" {
  type    = string
  default = "ollama/ollama:latest"
}

variable "ollama_models" {
  description = "List of models to preload in Ollama"
  type        = list(string)
  default     = ["neural-chat", "mistral"]
}

variable "model_router_image" {
  type    = string
  default = "kc/model-router:latest"
}

variable "gpu_available" {
  description = "Whether GPU is available on host"
  type        = bool
  default     = false
}

variable "ai_memory_gb" {
  description = "Memory allocated for AI workloads (GB)"
  type        = number
  default     = 16
}

variable "tags" {
  type = map(string)
  default = {}
}
