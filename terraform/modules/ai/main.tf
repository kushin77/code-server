# @file terraform/modules/ai/main.tf
# @description AI/ML services configuration (Ollama, inference)

output "ai_services_config" {
  description = "AI services configuration"
  value = {
    ollama_enabled = true
    models         = var.ollama_models
    gpu_available  = var.gpu_available
    memory_gb      = var.ai_memory_gb
    endpoint       = "http://ollama-models:11434"
  }
}

output "ollama_preload_script" {
  description = "Script to preload Ollama models"
  value = join("\n", [
    "#!/bin/bash",
    "# Preload Ollama models",
    for model in var.ollama_models : "docker exec ollama-models ollama pull ${model}"
  ])
}
