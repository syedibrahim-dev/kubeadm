#!/usr/bin/env bash
set -euo pipefail

# Capture Terraform's JSON input before the heredoc consumes stdin.
# python3 - <<'PY' uses the heredoc as its stdin (the script source),
# so sys.stdin would read the script itself — not the Terraform query.
# Exporting via env var is the correct workaround.
TERRAFORM_INPUT=$(cat)
export TERRAFORM_INPUT

python3 <<'PY'
import json, os, subprocess, sys, time

query = json.loads(os.environ["TERRAFORM_INPUT"])
region = query.get("aws_region", "")
kubeconfig = query.get("kubeconfig_path", "")
namespace = query.get("namespace", "")
service_name = query.get("service_name", "")

if not region or not kubeconfig or not namespace or not service_name:
    raise SystemExit("Missing required input: aws_region, kubeconfig_path, namespace, service_name")

env = os.environ.copy()
env["KUBECONFIG"] = kubeconfig

# Wait for Service to have a load balancer hostname
lb_dns = ""
deadline = time.time() + 900  # 15 minutes
while time.time() < deadline:
    try:
        out = subprocess.check_output(
            ["kubectl", "-n", namespace, "get", "svc", service_name, "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}"],
            env=env,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            lb_dns = out
            break
    except Exception:
        pass
    time.sleep(10)

if not lb_dns:
    raise SystemExit(f"Timed out waiting for Service {namespace}/{service_name} to get a load balancer hostname")

# Find the LB ARN by matching DNSName
arn = subprocess.check_output(
    [
        "aws",
        "elbv2",
        "describe-load-balancers",
        "--region",
        region,
        "--query",
        f"LoadBalancers[?DNSName=='{lb_dns}'].LoadBalancerArn | [0]",
        "--output",
        "text",
    ],
    text=True,
).strip()

if not arn or arn == "None":
    raise SystemExit(f"Could not find ELBv2 load balancer ARN for DNS name: {lb_dns}")

# Get the per-AZ private IP addresses for the NLB
ips_out = subprocess.check_output(
    [
        "aws",
        "elbv2",
        "describe-load-balancers",
        "--region",
        region,
        "--load-balancer-arns",
        arn,
        "--query",
        "LoadBalancers[0].AvailabilityZones[].LoadBalancerAddresses[].IpAddress",
        "--output",
        "text",
    ],
    text=True,
).strip()

# aws cli returns whitespace-separated IPs
ips = [ip for ip in ips_out.split() if ip]

print(json.dumps({
    "ips": ",".join(ips),
    "dns_name": lb_dns,
    "lb_arn": arn,
}))
PY
