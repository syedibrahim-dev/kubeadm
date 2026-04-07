output "nlb_dns_name" {
  description = "Public DNS name of the NLB"
  value       = aws_lb.k8s_nlb.dns_name
}
