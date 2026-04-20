output "grafana_application_id" {
  description = "Cloudflare Access application ID for Grafana"
  value       = cloudflare_access_application.grafana.id
}

output "prometheus_application_id" {
  description = "Cloudflare Access application ID for Prometheus"
  value       = cloudflare_access_application.prometheus.id
}

output "alertmanager_application_id" {
  description = "Cloudflare Access application ID for AlertManager"
  value       = cloudflare_access_application.alertmanager.id
}

output "jaeger_application_id" {
  description = "Cloudflare Access application ID for Jaeger"
  value       = cloudflare_access_application.jaeger.id
}

output "ci_prometheus_service_token_client_id" {
  description = "CI service token client ID for Prometheus (use as CF-Access-Client-Id header)"
  value       = cloudflare_access_service_token.ci_prometheus.client_id
  sensitive   = true
}

output "ci_prometheus_service_token_client_secret" {
  description = "CI service token client secret for Prometheus (use as CF-Access-Client-Secret header)"
  value       = cloudflare_access_service_token.ci_prometheus.client_secret
  sensitive   = true
}

output "ci_grafana_service_token_client_id" {
  description = "CI service token client ID for Grafana"
  value       = cloudflare_access_service_token.ci_grafana.client_id
  sensitive   = true
}

output "ci_grafana_service_token_client_secret" {
  description = "CI service token client secret for Grafana"
  value       = cloudflare_access_service_token.ci_grafana.client_secret
  sensitive   = true
}

output "logpush_job_id" {
  description = "Cloudflare Logpush job ID for Access audit log (empty if logpush_r2_bucket not set)"
  value       = length(cloudflare_logpush_job.access_audit_log) > 0 ? cloudflare_logpush_job.access_audit_log[0].id : ""
}
