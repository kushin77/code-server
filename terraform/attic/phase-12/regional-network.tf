# Phase 12.1: Regional Network Configuration
# This file sets up subnets, NAT gateways, and network infrastructure per region

# Variables for regional configuration
variable "availability_zones_us_west" {
  type        = list(string)
  description = "Availability zones for US West region"
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "availability_zones_eu_west" {
  type        = list(string)
  description = "Availability zones for EU West region"
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "availability_zones_ap_south" {
  type        = list(string)
  description = "Availability zones for AP South region"
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "primary_region" {
  type        = string
  description = "Primary region (US West)"
  default     = "us-west-2"
}

variable "secondary_region" {
  type        = string
  description = "Secondary region (EU West)"
  default     = "eu-west-1"
}

variable "tertiary_region" {
  type        = string
  description = "Tertiary region (AP South)"
  default     = "ap-south-1"
}

variable "cidr_us_west" {
  type        = string
  description = "CIDR block for US West region"
  default     = "10.0.0.0/16"
}

variable "cidr_eu_west" {
  type        = string
  description = "CIDR block for EU West region"
  default     = "10.1.0.0/16"
}

variable "cidr_ap_south" {
  type        = string
  description = "CIDR block for AP South region"
  default     = "10.2.0.0/16"
}

# US West Region Subnets
resource "aws_subnet" "us_west_public" {
  for_each = toset(var.availability_zones_us_west)

  provider                = aws.us_west
  vpc_id                  = var.vpc_id_us_west
  availability_zone       = each.value
  cidr_block              = "10.0.${index(var.availability_zones_us_west, each.value)}.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-us-west-public-${replace(each.value, "us-west-2", "")}"
    Type = "Public"
  }
}

resource "aws_subnet" "us_west_private" {
  for_each = toset(var.availability_zones_us_west)

  provider          = aws.us_west
  vpc_id            = var.vpc_id_us_west
  availability_zone = each.value
  cidr_block        = "10.0.${100 + index(var.availability_zones_us_west, each.value)}.0/24"

  tags = {
    Name = "subnet-us-west-private-${replace(each.value, "us-west-2", "")}"
    Type = "Private"
  }
}

# EU West Region Subnets
resource "aws_subnet" "eu_west_public" {
  for_each = toset(var.availability_zones_eu_west)

  provider                = aws.eu_west
  vpc_id                  = var.vpc_id_eu_west
  availability_zone       = each.value
  cidr_block              = "10.1.${index(var.availability_zones_eu_west, each.value)}.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-eu-west-public-${replace(each.value, "eu-west-1", "")}"
    Type = "Public"
  }
}

resource "aws_subnet" "eu_west_private" {
  for_each = toset(var.availability_zones_eu_west)

  provider          = aws.eu_west
  vpc_id            = var.vpc_id_eu_west
  availability_zone = each.value
  cidr_block        = "10.1.${100 + index(var.availability_zones_eu_west, each.value)}.0/24"

  tags = {
    Name = "subnet-eu-west-private-${replace(each.value, "eu-west-1", "")}"
    Type = "Private"
  }
}

# AP South Region Subnets
resource "aws_subnet" "ap_south_public" {
  for_each = toset(var.availability_zones_ap_south)

  provider                = aws.ap_south
  vpc_id                  = var.vpc_id_ap_south
  availability_zone       = each.value
  cidr_block              = "10.2.${index(var.availability_zones_ap_south, each.value)}.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-ap-south-public-${replace(each.value, "ap-south-1", "")}"
    Type = "Public"
  }
}

resource "aws_subnet" "ap_south_private" {
  for_each = toset(var.availability_zones_ap_south)

  provider          = aws.ap_south
  vpc_id            = var.vpc_id_ap_south
  availability_zone = each.value
  cidr_block        = "10.2.${100 + index(var.availability_zones_ap_south, each.value)}.0/24"

  tags = {
    Name = "subnet-ap-south-private-${replace(each.value, "ap-south-1", "")}"
    Type = "Private"
  }
}

# Elastic IPs for NAT Gateways (US West)
resource "aws_eip" "nat_us_west" {
  for_each = toset(var.availability_zones_us_west)

  provider = aws.us_west
  domain   = "vpc"

  tags = {
    Name = "eip-nat-us-west-${replace(each.value, "us-west-2", "")}"
  }

  depends_on = [var.vpc_id_us_west]
}

# NAT Gateways (US West) - One per AZ for redundancy
resource "aws_nat_gateway" "us_west" {
  for_each = toset(var.availability_zones_us_west)

  provider      = aws.us_west
  allocation_id = aws_eip.nat_us_west[each.value].id
  subnet_id     = aws_subnet.us_west_public[each.value].id

  tags = {
    Name = "nat-us-west-${replace(each.value, "us-west-2", "")}"
  }

  depends_on = [var.vpc_id_us_west]
}

# Elastic IPs for NAT Gateways (EU West)
resource "aws_eip" "nat_eu_west" {
  for_each = toset(var.availability_zones_eu_west)

  provider = aws.eu_west
  domain   = "vpc"

  tags = {
    Name = "eip-nat-eu-west-${replace(each.value, "eu-west-1", "")}"
  }

  depends_on = [var.vpc_id_eu_west]
}

# NAT Gateways (EU West)
resource "aws_nat_gateway" "eu_west" {
  for_each = toset(var.availability_zones_eu_west)

  provider      = aws.eu_west
  allocation_id = aws_eip.nat_eu_west[each.value].id
  subnet_id     = aws_subnet.eu_west_public[each.value].id

  tags = {
    Name = "nat-eu-west-${replace(each.value, "eu-west-1", "")}"
  }

  depends_on = [var.vpc_id_eu_west]
}

# Elastic IPs for NAT Gateways (AP South)
resource "aws_eip" "nat_ap_south" {
  for_each = toset(var.availability_zones_ap_south)

  provider = aws.ap_south
  domain   = "vpc"

  tags = {
    Name = "eip-nat-ap-south-${replace(each.value, "ap-south-1", "")}"
  }

  depends_on = [var.vpc_id_ap_south]
}

# NAT Gateways (AP South)
resource "aws_nat_gateway" "ap_south" {
  for_each = toset(var.availability_zones_ap_south)

  provider      = aws.ap_south
  allocation_id = aws_eip.nat_ap_south[each.value].id
  subnet_id     = aws_subnet.ap_south_public[each.value].id

  tags = {
    Name = "nat-ap-south-${replace(each.value, "ap-south-1", "")}"
  }

  depends_on = [var.vpc_id_ap_south]
}

# Private Route Tables and Routes (US West)
resource "aws_route_table" "us_west_private" {
  for_each = toset(var.availability_zones_us_west)

  provider = aws.us_west
  vpc_id   = var.vpc_id_us_west

  tags = {
    Name = "rt-us-west-private-${replace(each.value, "us-west-2", "")}"
  }
}

resource "aws_route_table_association" "us_west_private" {
  for_each = toset(var.availability_zones_us_west)

  provider       = aws.us_west
  subnet_id      = aws_subnet.us_west_private[each.value].id
  route_table_id = aws_route_table.us_west_private[each.value].id
}

resource "aws_route" "us_west_nat" {
  for_each = toset(var.availability_zones_us_west)

  provider               = aws.us_west
  route_table_id         = aws_route_table.us_west_private[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.us_west[each.value].id
}

# Private Route Tables and Routes (EU West)
resource "aws_route_table" "eu_west_private" {
  for_each = toset(var.availability_zones_eu_west)

  provider = aws.eu_west
  vpc_id   = var.vpc_id_eu_west

  tags = {
    Name = "rt-eu-west-private-${replace(each.value, "eu-west-1", "")}"
  }
}

resource "aws_route_table_association" "eu_west_private" {
  for_each = toset(var.availability_zones_eu_west)

  provider       = aws.eu_west
  subnet_id      = aws_subnet.eu_west_private[each.value].id
  route_table_id = aws_route_table.eu_west_private[each.value].id
}

resource "aws_route" "eu_west_nat" {
  for_each = toset(var.availability_zones_eu_west)

  provider               = aws.eu_west
  route_table_id         = aws_route_table.eu_west_private[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.eu_west[each.value].id
}

# Private Route Tables and Routes (AP South)
resource "aws_route_table" "ap_south_private" {
  for_each = toset(var.availability_zones_ap_south)

  provider = aws.ap_south
  vpc_id   = var.vpc_id_ap_south

  tags = {
    Name = "rt-ap-south-private-${replace(each.value, "ap-south-1", "")}"
  }
}

resource "aws_route_table_association" "ap_south_private" {
  for_each = toset(var.availability_zones_ap_south)

  provider       = aws.ap_south
  subnet_id      = aws_subnet.ap_south_private[each.value].id
  route_table_id = aws_route_table.ap_south_private[each.value].id
}

resource "aws_route" "ap_south_nat" {
  for_each = toset(var.availability_zones_ap_south)

  provider               = aws.ap_south
  route_table_id         = aws_route_table.ap_south_private[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ap_south[each.value].id
}

# Outputs
output "us_west_public_subnets" {
  value       = [for subnet in aws_subnet.us_west_public : subnet.id]
  description = "Public subnet IDs in US West"
}

output "eu_west_public_subnets" {
  value       = [for subnet in aws_subnet.eu_west_public : subnet.id]
  description = "Public subnet IDs in EU West"
}

output "ap_south_public_subnets" {
  value       = [for subnet in aws_subnet.ap_south_public : subnet.id]
  description = "Public subnet IDs in AP South"
}

output "us_west_private_subnets" {
  value       = [for subnet in aws_subnet.us_west_private : subnet.id]
  description = "Private subnet IDs in US West"
}

output "eu_west_private_subnets" {
  value       = [for subnet in aws_subnet.eu_west_private : subnet.id]
  description = "Private subnet IDs in EU West"
}

output "ap_south_private_subnets" {
  value       = [for subnet in aws_subnet.ap_south_private : subnet.id]
  description = "Private subnet IDs in AP South"
}
