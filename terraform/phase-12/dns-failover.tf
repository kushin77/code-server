# Phase 12.1: Route53 Geographic Routing and Failover Configuration
# This file implements geo-DNS routing with automatic failover capabilities

# Variables for Route53 configuration
variable "primary_domain" {
  type        = string
  description = "Primary domain for multi-region routing"
  default     = "api.multi-region.example.com"
}

variable "health_check_interval" {
  type        = number
  description = "Health check interval in seconds"
  default     = 10
}

variable "health_check_failure_threshold" {
  type        = number
  description = "Number of failed checks before marking unhealthy"
  default     = 3
}

# Health check for US West endpoint
resource "aws_route53_health_check" "us_west" {
  type              = "HTTPS"
  resource_path     = "/health"
  fqdn              = aws_lb.nlb_us_west.dns_name
  port              = 443
  protocol          = "HTTPS"
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold

  tags = {
    Name = "health-check-us-west"
  }
}

# Health check for EU West endpoint
resource "aws_route53_health_check" "eu_west" {
  type              = "HTTPS"
  resource_path     = "/health"
  fqdn              = aws_lb.nlb_eu_west.dns_name
  port              = 443
  protocol          = "HTTPS"
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold

  tags = {
    Name = "health-check-eu-west"
  }
}

# Health check for AP South endpoint
resource "aws_route53_health_check" "ap_south" {
  type              = "HTTPS"
  resource_path     = "/health"
  fqdn              = aws_lb.nlb_ap_south.dns_name
  port              = 443
  protocol          = "HTTPS"
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold

  tags = {
    Name = "health-check-ap-south"
  }
}

# Primary Route53 hosted zone (assumes it already exists)
data "aws_route53_zone" "primary" {
  name = "multi-region.example.com"
}

# Geographic routing policy for US West
resource "aws_route53_record" "us_west_geo" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "A"

  alias {
    name                   = aws_lb.nlb_us_west.dns_name
    zone_id                = aws_lb.nlb_us_west.zone_id
    evaluate_target_health = true
  }

  set_identifier = "us-west-2"
  geolocation_location {
    country = "US"
  }

  health_check_id = aws_route53_health_check.us_west.id
}

# Geographic routing policy for EU West
resource "aws_route53_record" "eu_west_geo" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "A"

  alias {
    name                   = aws_lb.nlb_eu_west.dns_name
    zone_id                = aws_lb.nlb_eu_west.zone_id
    evaluate_target_health = true
  }

  set_identifier = "eu-west-1"
  geolocation_location {
    country = "GB"  # UK as proxy for EU
  }

  health_check_id = aws_route53_health_check.eu_west.id
}

# Geographic routing policy for AP South
resource "aws_route53_record" "ap_south_geo" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "A"

  alias {
    name                   = aws_lb.nlb_ap_south.dns_name
    zone_id                = aws_lb.nlb_ap_south.zone_id
    evaluate_target_health = true
  }

  set_identifier = "ap-south-1"
  geolocation_location {
    country = "IN"  # India as proxy for AP South
  }

  health_check_id = aws_route53_health_check.ap_south.id
}

# Fallback routing default location (for unmatched geolocation)
resource "aws_route53_record" "default_geo" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "A"

  alias {
    name                   = aws_lb.nlb_us_west.dns_name
    zone_id                = aws_lb.nlb_us_west.zone_id
    evaluate_target_health = true
  }

  set_identifier = "default"
  geolocation_location {
    country = "*"  # Default for all other locations
  }

  health_check_id = aws_route53_health_check.us_west.id
}

# Database-specific routing (PostgreSQL multi-primary endpoints)
resource "aws_route53_record" "postgres_us_west" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "postgres.us-west.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_us_west.dns_name
    zone_id                = aws_lb.nlb_us_west.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.us_west.id
}

resource "aws_route53_record" "postgres_eu_west" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "postgres.eu-west.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_eu_west.dns_name
    zone_id                = aws_lb.nlb_eu_west.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.eu_west.id
}

resource "aws_route53_record" "postgres_ap_south" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "postgres.ap-south.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_ap_south.dns_name
    zone_id                = aws_lb.nlb_ap_south.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.ap_south.id
}

# Setup traffic policy for advanced routing (latency-based as backup)
resource "aws_route53_record" "latency_us_west" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "latency.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_us_west.dns_name
    zone_id                = aws_lb.nlb_us_west.zone_id
    evaluate_target_health = true
  }

  set_identifier = "latency-us-west"
  latency_routing_policy {
    region = "us-west-2"
  }

  health_check_id = aws_route53_health_check.us_west.id
}

resource "aws_route53_record" "latency_eu_west" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "latency.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_eu_west.dns_name
    zone_id                = aws_lb.nlb_eu_west.zone_id
    evaluate_target_health = true
  }

  set_identifier = "latency-eu-west"
  latency_routing_policy {
    region = "eu-west-1"
  }

  health_check_id = aws_route53_health_check.eu_west.id
}

resource "aws_route53_record" "latency_ap_south" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "latency.${data.aws_route53_zone.primary.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb_ap_south.dns_name
    zone_id                = aws_lb.nlb_ap_south.zone_id
    evaluate_target_health = true
  }

  set_identifier = "latency-ap-south"
  latency_routing_policy {
    region = "ap-south-1"
  }

  health_check_id = aws_route53_health_check.ap_south.id
}

# CloudWatch dashboard for monitoring Route53 health
resource "aws_cloudwatch_dashboard" "route53_health" {
  dashboard_name = "phase-12-route53-health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.us_west.id],
            [".", ".", ".", aws_route53_health_check.eu_west.id],
            [".", ".", ".", aws_route53_health_check.ap_south.id]
          ]
          period = 60
          stat   = "Average"
          region = "us-west-2"
          title  = "Route53 Health Check Status"
        }
      }
    ]
  })
}

# SNS topic for DNS failover alerts
resource "aws_sns_topic" "dns_failover_alerts" {
  name = "phase-12-dns-failover-alerts"

  tags = {
    Name = "dns-failover-alerts"
  }
}

# Alarm for US West health check failure
resource "aws_cloudwatch_metric_alarm" "health_check_us_west" {
  alarm_name          = "route53-health-check-us-west-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = aws_route53_health_check.us_west.id
  }

  alarm_actions = [aws_sns_topic.dns_failover_alerts.arn]
}

# Alarm for EU West health check failure
resource "aws_cloudwatch_metric_alarm" "health_check_eu_west" {
  alarm_name          = "route53-health-check-eu-west-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = aws_route53_health_check.eu_west.id
  }

  alarm_actions = [aws_sns_topic.dns_failover_alerts.arn]
}

# Alarm for AP South health check failure
resource "aws_cloudwatch_metric_alarm" "health_check_ap_south" {
  alarm_name          = "route53-health-check-ap-south-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = aws_route53_health_check.ap_south.id
  }

  alarm_actions = [aws_sns_topic.dns_failover_alerts.arn]
}

# Outputs
output "route53_health_check_us_west_id" {
  value       = aws_route53_health_check.us_west.id
  description = "Health check ID for US West endpoint"
}

output "route53_health_check_eu_west_id" {
  value       = aws_route53_health_check.eu_west.id
  description = "Health check ID for EU West endpoint"
}

output "route53_health_check_ap_south_id" {
  value       = aws_route53_health_check.ap_south.id
  description = "Health check ID for AP South endpoint"
}

output "primary_domain_name" {
  value       = var.primary_domain
  description = "Primary domain for multi-region routing"
}

output "postgres_endpoints" {
  value = {
    us_west = aws_route53_record.postgres_us_west.fqdn
    eu_west = aws_route53_record.postgres_eu_west.fqdn
    ap_south = aws_route53_record.postgres_ap_south.fqdn
  }
  description = "PostgreSQL endpoints per region"
}
