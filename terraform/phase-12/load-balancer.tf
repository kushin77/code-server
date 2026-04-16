# Phase 12.1: Regional Load Balancer Configuration
# This file sets up network and application load balancers per region with health checks

# Network Load Balancers per region for low-latency routing
resource "aws_lb" "nlb_us_west" {
  provider           = aws.us_west
  name               = "nlb-multi-region-us-west"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.us_west_public : subnet.id]

  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "nlb-us-west"
  }
}

resource "aws_lb" "nlb_eu_west" {
  provider           = aws.eu_west
  name               = "nlb-multi-region-eu-west"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.eu_west_public : subnet.id]

  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "nlb-eu-west"
  }
}

resource "aws_lb" "nlb_ap_south" {
  provider           = aws.ap_south
  name               = "nlb-multi-region-ap-south"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.ap_south_public : subnet.id]

  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "nlb-ap-south"
  }
}

# TCP Target Groups for Application Servers (port 8080)
resource "aws_lb_target_group" "app_us_west" {
  provider    = aws.us_west
  name        = "tg-app-us-west"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id_us_west
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "8080"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-app-us-west"
  }
}

resource "aws_lb_target_group" "app_eu_west" {
  provider    = aws.eu_west
  name        = "tg-app-eu-west"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id_eu_west
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "8080"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-app-eu-west"
  }
}

resource "aws_lb_target_group" "app_ap_south" {
  provider    = aws.ap_south
  name        = "tg-app-ap-south"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id_ap_south
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "8080"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-app-ap-south"
  }
}

# TCP Target Groups for PostgreSQL (port 5432)
resource "aws_lb_target_group" "postgres_us_west" {
  provider    = aws.us_west
  name        = "tg-postgres-us-west"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = var.vpc_id_us_west
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "5432"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-postgres-us-west"
  }
}

resource "aws_lb_target_group" "postgres_eu_west" {
  provider    = aws.eu_west
  name        = "tg-postgres-eu-west"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = var.vpc_id_eu_west
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "5432"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-postgres-eu-west"
  }
}

resource "aws_lb_target_group" "postgres_ap_south" {
  provider    = aws.ap_south
  name        = "tg-postgres-ap-south"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = var.vpc_id_ap_south
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    port                = "5432"
    protocol            = "TCP"
  }

  tags = {
    Name = "tg-postgres-ap-south"
  }
}

# NLB Listeners for App Traffic (US West)
resource "aws_lb_listener" "nlb_app_us_west" {
  provider          = aws.us_west
  load_balancer_arn = aws_lb.nlb_us_west.arn
  port              = "8080"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_us_west.arn
  }
}

# NLB Listeners for PostgreSQL (US West)
resource "aws_lb_listener" "nlb_postgres_us_west" {
  provider          = aws.us_west
  load_balancer_arn = aws_lb.nlb_us_west.arn
  port              = "5432"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgres_us_west.arn
  }
}

# NLB Listeners for App Traffic (EU West)
resource "aws_lb_listener" "nlb_app_eu_west" {
  provider          = aws.eu_west
  load_balancer_arn = aws_lb.nlb_eu_west.arn
  port              = "8080"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_eu_west.arn
  }
}

# NLB Listeners for PostgreSQL (EU West)
resource "aws_lb_listener" "nlb_postgres_eu_west" {
  provider          = aws.eu_west
  load_balancer_arn = aws_lb.nlb_eu_west.arn
  port              = "5432"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgres_eu_west.arn
  }
}

# NLB Listeners for App Traffic (AP South)
resource "aws_lb_listener" "nlb_app_ap_south" {
  provider          = aws.ap_south
  load_balancer_arn = aws_lb.nlb_ap_south.arn
  port              = "8080"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_ap_south.arn
  }
}

# NLB Listeners for PostgreSQL (AP South)
resource "aws_lb_listener" "nlb_postgres_ap_south" {
  provider          = aws.ap_south
  load_balancer_arn = aws_lb.nlb_ap_south.arn
  port              = "5432"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgres_ap_south.arn
  }
}

# CloudWatch Alarms for NLB Health (US West)
resource "aws_cloudwatch_metric_alarm" "nlb_us_west_unhealthy_hosts" {
  provider            = aws.us_west
  alarm_name          = "nlb-us-west-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.nlb_us_west.arn_suffix
  }

  alarm_actions = []
}

# CloudWatch Alarms for NLB Health (EU West)
resource "aws_cloudwatch_metric_alarm" "nlb_eu_west_unhealthy_hosts" {
  provider            = aws.eu_west
  alarm_name          = "nlb-eu-west-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.nlb_eu_west.arn_suffix
  }

  alarm_actions = []
}

# CloudWatch Alarms for NLB Health (AP South)
resource "aws_cloudwatch_metric_alarm" "nlb_ap_south_unhealthy_hosts" {
  provider            = aws.ap_south
  alarm_name          = "nlb-ap-south-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.nlb_ap_south.arn_suffix
  }

  alarm_actions = []
}

# Outputs
output "nlb_us_west_dns" {
  value       = aws_lb.nlb_us_west.dns_name
  description = "DNS name of NLB in US West region"
}

output "nlb_eu_west_dns" {
  value       = aws_lb.nlb_eu_west.dns_name
  description = "DNS name of NLB in EU West region"
}

output "nlb_ap_south_dns" {
  value       = aws_lb.nlb_ap_south.dns_name
  description = "DNS name of NLB in AP South region"
}

output "target_group_app_us_west_arn" {
  value       = aws_lb_target_group.app_us_west.arn
  description = "ARN of app target group in US West"
}

output "target_group_app_eu_west_arn" {
  value       = aws_lb_target_group.app_eu_west.arn
  description = "ARN of app target group in EU West"
}

output "target_group_app_ap_south_arn" {
  value       = aws_lb_target_group.app_ap_south.arn
  description = "ARN of app target group in AP South"
}
