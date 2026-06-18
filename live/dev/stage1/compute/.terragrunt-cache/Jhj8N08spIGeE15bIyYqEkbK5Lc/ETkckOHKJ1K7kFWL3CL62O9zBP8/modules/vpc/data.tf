# Availability zones are discovered dynamically so the module is region-agnostic.
# AZ[0] hosts all K8s nodes (control plane + workers) and the NAT Gateway.
# AZ[1] provides the second public/private subnet pair required by the ALB
# (ALB requires subnets in at least 2 AZs).
data "aws_availability_zones" "available" {
  state = "available"
}
