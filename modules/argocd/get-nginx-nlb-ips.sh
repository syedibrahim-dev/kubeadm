#!/usr/bin/env bash
set -euo pipefail

# Capture Terraform's JSON input before the heredoc consumes stdin.
# python3 - <<'PY' uses the heredoc as its stdin (the script source),
# so sys.stdin would read the script itself — not the Terraform query.
# Exporting via env var is the correct workaround.
TERRAFORM_INPUT=$(cat)
export TERRAFORM_INPUT

python3 <<'PY'
import json, os, socket, subprocess, sys, time

query = json.loads(os.environ["TERRAFORM_INPUT"])
region      = query.get("aws_region", "")
kubeconfig  = query.get("kubeconfig_path", "")
namespace   = query.get("namespace", "")
service_name = query.get("service_name", "")

if not region or not kubeconfig or not namespace or not service_name:
    raise SystemExit("Missing required input: aws_region, kubeconfig_path, namespace, service_name")

env = os.environ.copy()
env["KUBECONFIG"] = kubeconfig

# ── Step 1: wait for the Service to receive an NLB hostname ──────────────────
lb_dns = ""
deadline = time.time() + 900  # 15 minutes
while time.time() < deadline:
    try:
        out = subprocess.check_output(
            ["kubectl", "-n", namespace, "get", "svc", service_name,
             "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}"],
            env=env, stderr=subprocess.DEVNULL, text=True,
        ).strip()
        if out:
            lb_dns = out
            break
    except Exception:
        pass
    time.sleep(10)

if not lb_dns:
    raise SystemExit(f"Timed out waiting for Service {namespace}/{service_name} to get an NLB hostname")

# ── Step 2: resolve the NLB DNS to private IPs ───────────────────────────────
# describe-load-balancers does NOT populate LoadBalancerAddresses.IpAddress
# for CCM-provisioned NLBs with dynamic IP assignment — DNS resolution is the
# reliable way to discover the actual private IPs.
ips = []
deadline2 = time.time() + 120  # 2 minutes for DNS propagation
while time.time() < deadline2:
    try:
        resolved = sorted(set([
            r[4][0]
            for r in socket.getaddrinfo(lb_dns, None, socket.AF_INET)
        ]))
        if resolved:
            ips = resolved
            break
    except Exception:
        pass
    time.sleep(10)

if not ips:
    raise SystemExit(f"Could not resolve any IPs for NLB DNS: {lb_dns}")

print(json.dumps({
    "ips":      ",".join(ips),
    "dns_name": lb_dns,
}))
PY
