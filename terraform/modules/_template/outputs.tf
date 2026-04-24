output "module_name" {
  description = "Module name used for consistent labelling."
  value       = var.module_name
}

output "module_labels" {
  description = "Merged labels available to resources in this module."
  value       = local.module_labels
}