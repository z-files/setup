terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

#------------------------------------------------------------------------------
# VPC A (Inspection VPC with Network Firewall)
#------------------------------------------------------------------------------
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc-a"
  }
}

resource "aws_subnet" "vpc_a_workload" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = cidrsubnet(var.vpc_a_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-vpc-a-workload-${local.azs[count.index]}"
  }
}

resource "aws_subnet" "vpc_a_tgw" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = cidrsubnet(var.vpc_a_cidr, 4, count.index + 4)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-vpc-a-tgw-${local.azs[count.index]}"
  }
}

resource "aws_subnet" "vpc_a_firewall" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = cidrsubnet(var.vpc_a_cidr, 4, count.index + 8)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-vpc-a-firewall-${local.azs[count.index]}"
  }
}

#------------------------------------------------------------------------------
# VPC B (Workload VPC)
#------------------------------------------------------------------------------
resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc-b"
  }
}

resource "aws_subnet" "vpc_b_workload" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.vpc_b.id
  cidr_block        = cidrsubnet(var.vpc_b_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-vpc-b-workload-${local.azs[count.index]}"
  }
}

resource "aws_subnet" "vpc_b_tgw" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.vpc_b.id
  cidr_block        = cidrsubnet(var.vpc_b_cidr, 4, count.index + 4)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-vpc-b-tgw-${local.azs[count.index]}"
  }
}

#------------------------------------------------------------------------------
# Transit Gateway
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Transit Gateway for VPC connectivity"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "${var.name_prefix}-tgw"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_a" {
  subnet_ids                                      = aws_subnet.vpc_a_tgw[*].id
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = aws_vpc.vpc_a.id
  appliance_mode_support                          = "enable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${var.name_prefix}-tgw-attach-vpc-a"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_b" {
  subnet_ids                                      = aws_subnet.vpc_b_tgw[*].id
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = aws_vpc.vpc_b.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${var.name_prefix}-tgw-attach-vpc-b"
  }
}

#------------------------------------------------------------------------------
# Transit Gateway Route Tables
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${var.name_prefix}-tgw-rt-inspection"
  }
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${var.name_prefix}-tgw-rt-spoke"
  }
}

# Associate VPC A (inspection) with inspection route table
resource "aws_ec2_transit_gateway_route_table_association" "vpc_a" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_a.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Associate VPC B (spoke) with spoke route table
resource "aws_ec2_transit_gateway_route_table_association" "vpc_b" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Spoke route table: all traffic goes to inspection VPC
resource "aws_ec2_transit_gateway_route" "spoke_to_inspection" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_a.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Inspection route table: route to VPC B
resource "aws_ec2_transit_gateway_route" "inspection_to_vpc_b" {
  destination_cidr_block         = var.vpc_b_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

#------------------------------------------------------------------------------
# AWS Network Firewall
#------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.name_prefix}-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
    }
  }

  tags = {
    Name = "${var.name_prefix}-firewall-policy"
  }
}

resource "aws_networkfirewall_rule_group" "stateful" {
  capacity = 100
  name     = "${var.name_prefix}-stateful-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "IP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["1"]
        }
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-stateful-rules"
  }
}

resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.name_prefix}-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.vpc_a.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.vpc_a_firewall[*].id
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-network-firewall"
  }
}

#------------------------------------------------------------------------------
# VPC A Route Tables
#------------------------------------------------------------------------------
# Workload subnet route table
resource "aws_route_table" "vpc_a_workload" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "${var.name_prefix}-vpc-a-workload-rt"
  }
}

resource "aws_route" "vpc_a_workload_to_tgw" {
  route_table_id         = aws_route_table.vpc_a_workload.id
  destination_cidr_block = var.vpc_b_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc_a]
}

resource "aws_route_table_association" "vpc_a_workload" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.vpc_a_workload[count.index].id
  route_table_id = aws_route_table.vpc_a_workload.id
}

# TGW subnet route tables (per AZ for firewall endpoints)
resource "aws_route_table" "vpc_a_tgw" {
  count  = length(local.azs)
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "${var.name_prefix}-vpc-a-tgw-rt-${local.azs[count.index]}"
  }
}

resource "aws_route" "vpc_a_tgw_to_firewall" {
  count                  = length(local.azs)
  route_table_id         = aws_route_table.vpc_a_tgw[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = [for ep in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : ep.attachment[0].endpoint_id if ep.availability_zone == local.azs[count.index]][0]
}

resource "aws_route_table_association" "vpc_a_tgw" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.vpc_a_tgw[count.index].id
  route_table_id = aws_route_table.vpc_a_tgw[count.index].id
}

# Firewall subnet route tables (per AZ)
resource "aws_route_table" "vpc_a_firewall" {
  count  = length(local.azs)
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "${var.name_prefix}-vpc-a-firewall-rt-${local.azs[count.index]}"
  }
}

resource "aws_route" "vpc_a_firewall_to_tgw" {
  count                  = length(local.azs)
  route_table_id         = aws_route_table.vpc_a_firewall[count.index].id
  destination_cidr_block = var.vpc_b_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc_a]
}

resource "aws_route_table_association" "vpc_a_firewall" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.vpc_a_firewall[count.index].id
  route_table_id = aws_route_table.vpc_a_firewall[count.index].id
}

#------------------------------------------------------------------------------
# VPC B Route Tables
#------------------------------------------------------------------------------
resource "aws_route_table" "vpc_b_workload" {
  vpc_id = aws_vpc.vpc_b.id

  tags = {
    Name = "${var.name_prefix}-vpc-b-workload-rt"
  }
}

resource "aws_route" "vpc_b_workload_to_tgw" {
  route_table_id         = aws_route_table.vpc_b_workload.id
  destination_cidr_block = var.vpc_a_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc_b]
}

resource "aws_route_table_association" "vpc_b_workload" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.vpc_b_workload[count.index].id
  route_table_id = aws_route_table.vpc_b_workload.id
}

resource "aws_route_table" "vpc_b_tgw" {
  vpc_id = aws_vpc.vpc_b.id

  tags = {
    Name = "${var.name_prefix}-vpc-b-tgw-rt"
  }
}

resource "aws_route_table_association" "vpc_b_tgw" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.vpc_b_tgw[count.index].id
  route_table_id = aws_route_table.vpc_b_tgw.id
}
