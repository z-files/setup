output "vpc_a_id" {
  description = "VPC A ID"
  value       = aws_vpc.vpc_a.id
}

output "vpc_b_id" {
  description = "VPC B ID"
  value       = aws_vpc.vpc_b.id
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "network_firewall_id" {
  description = "Network Firewall ID"
  value       = aws_networkfirewall_firewall.main.id
}

output "network_firewall_endpoint_ids" {
  description = "Network Firewall endpoint IDs per AZ"
  value = {
    for state in aws_networkfirewall_firewall.main.firewall_status[0].sync_states :
    state.availability_zone => state.attachment[0].endpoint_id
  }
}

output "vpc_a_workload_subnet_ids" {
  description = "VPC A workload subnet IDs"
  value       = aws_subnet.vpc_a_workload[*].id
}

output "vpc_b_workload_subnet_ids" {
  description = "VPC B workload subnet IDs"
  value       = aws_subnet.vpc_b_workload[*].id
}
