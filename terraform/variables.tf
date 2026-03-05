variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "network"
}

variable "vpc_a_cidr" {
  description = "CIDR block for VPC A (inspection VPC)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vpc_b_cidr" {
  description = "CIDR block for VPC B (workload VPC)"
  type        = string
  default     = "10.2.0.0/16"
}
