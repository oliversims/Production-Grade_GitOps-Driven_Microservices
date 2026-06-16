#!/bin/bash
set -euo pipefail

# Tear down everything installed by run-platform-setup.sh + run-app-monitoring-setup.sh, in reverse order.
# Run BEFORE: terraform destroy (03_eks → 02_bastion → 01_vpc)
#
# Usage: /opt/bastion/delete-kubernetes-workloads.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
DNS_DOMAIN="oliver14.com"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
MANIFESTS_DIR="$REPO_DIR/gateway-api-manifests"
OBSERVABILITY_DIR="$REPO_DIR/observability"
ARGOCD_TARGET_GRP="$REPO_DIR/argocd/target-grp-config.yaml"
IMAGE_UPDATER_CR="$REPO_DIR/argocd/image-updater.yaml"
BOUTIQUE_APP_CR="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"
GRAFANA_ROUTE="$OBSERVABILITY_DIR/HTTProute-grafana.yaml"
GRAFANA_TG="$OBSERVABILITY_DIR/target-grp-grafana.yaml"
PROMETHEUS_ROUTE="$OBSERVABILITY_DIR/HTTProute-prometheus.yaml"
PROMETHEUS_TG="$OBSERVABILITY_DIR/target-grp-prometheus.yaml"

# Wait until a Kubernetes resource is gone. Skips quietly when already deleted.
wait_for_delete() {
  local resource="$1"
  local namespace="${2:-}"
  local timeout="${3:-180s}"

  kubectl get ${namespace:+-n "$namespace"} "$resource" >/dev/null 2>&1 \
    || { echo "$resource already gone."; return; }

  echo "Waiting for $resource to be fully removed..."
  kubectl wait ${namespace:+-n "$namespace"} --for=delete "$resource" --timeout="$timeout" \
    || echo "WARNING: Timed out waiting for $resource to be deleted."
}

# Uninstall a Helm release, then wait for its main deployment to disappear.
helm_uninstall_and_wait() {
  local release="$1"
  local namespace="$2"
  local deployment="$3"
  local timeout="${4:-180s}"

  helm uninstall "$release" -n "$namespace" 2>/dev/null || true
  wait_for_delete "deployment/$deployment" "$namespace" "$timeout"
}

# Exit 0 when managed External DNS records still exist in Route53; exit 1 when they are gone.
route53_managed_records_exist() {
  local zone_id
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$DNS_DOMAIN" \
    --query "HostedZones[?Name=='${DNS_DOMAIN}.'].Id" --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')
  [ -n "$zone_id" ] || return 1

  aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --output json 2>/dev/null \
    | python3 -c "
import json, sys
names = {
    'app.${DNS_DOMAIN}.', 'argocd.${DNS_DOMAIN}.',
    'grafana.${DNS_DOMAIN}.', 'prometheus.${DNS_DOMAIN}.',
    'aaaa-app.${DNS_DOMAIN}.', 'aaaa-argocd.${DNS_DOMAIN}.',
    'aaaa-grafana.${DNS_DOMAIN}.', 'aaaa-prometheus.${DNS_DOMAIN}.',
    'cname-app.${DNS_DOMAIN}.', 'cname-argocd.${DNS_DOMAIN}.',
    'cname-grafana.${DNS_DOMAIN}.', 'cname-prometheus.${DNS_DOMAIN}.',
}
records = json.load(sys.stdin).get('ResourceRecordSets', [])
sys.exit(0 if any(r['Name'] in names for r in records) else 1)
"
}

# Give External DNS time to remove Route53 records while it is still running.
wait_for_external_dns_cleanup() {
  local seconds="${1:-120}"
  local elapsed=0

  kubectl get deployment/external-dns -n external-dns >/dev/null 2>&1 \
    || { echo "External DNS not running — Route53 fallback will run after step 4."; return; }

  echo "Waiting up to ${seconds}s for External DNS to remove managed Route53 records..."
  while [ "$elapsed" -lt "$seconds" ]; do
    route53_managed_records_exist \
      && { echo "Route53 records for managed hostnames removed."; return; }
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "WARNING: Timed out waiting for External DNS Route53 cleanup — fallback will run after step 4."
}

# Delete any leftover app/argocd/grafana/prometheus records if External DNS did not finish in time.
cleanup_orphan_route53_records() {
  echo "Checking Route53 for orphaned managed records..."
  python3 <<PY
import json
import subprocess
import sys

DOMAIN = "${DNS_DOMAIN}"
MANAGED_NAMES = {
    f"app.{DOMAIN}.",
    f"argocd.{DOMAIN}.",
    f"grafana.{DOMAIN}.",
    f"prometheus.{DOMAIN}.",
    f"aaaa-app.{DOMAIN}.",
    f"aaaa-argocd.{DOMAIN}.",
    f"aaaa-grafana.{DOMAIN}.",
    f"aaaa-prometheus.{DOMAIN}.",
    f"cname-app.{DOMAIN}.",
    f"cname-argocd.{DOMAIN}.",
    f"cname-grafana.{DOMAIN}.",
    f"cname-prometheus.{DOMAIN}.",
}

def aws_json(*args):
    return json.loads(subprocess.check_output(["aws", *args], text=True))

zones = aws_json("route53", "list-hosted-zones-by-name", "--dns-name", DOMAIN, "--output", "json")
zone_id = next(
    (z["Id"].split("/")[-1] for z in zones["HostedZones"] if z["Name"] == f"{DOMAIN}."),
    None,
)
if not zone_id:
    print(f"WARNING: No hosted zone for {DOMAIN}")
    sys.exit(0)

records = aws_json(
    "route53", "list-resource-record-sets",
    "--hosted-zone-id", zone_id,
    "--output", "json",
)
changes = [
    {"Action": "DELETE", "ResourceRecordSet": rr}
    for rr in records["ResourceRecordSets"]
    if rr["Name"] in MANAGED_NAMES
]
if not changes:
    print("No orphaned Route53 records found.")
    sys.exit(0)

batch_path = "/tmp/route53-orphan-cleanup.json"
with open(batch_path, "w", encoding="utf-8") as fh:
    json.dump({"Changes": changes}, fh)

subprocess.check_call([
    "aws", "route53", "change-resource-record-sets",
    "--hosted-zone-id", zone_id,
    "--change-batch", f"file://{batch_path}",
])
print(f"Deleted {len(changes)} orphaned Route53 record(s).")
PY
}

echo ""
echo "========================================"
echo "  Kubernetes teardown started"
echo "  (reverse of post-setup + setup)"
echo "========================================"
echo ""

# Connect kubectl to the EKS cluster.
/opt/bastion/configure-kubeconfig.sh

# Pull delete manifests from GitHub (argocd, observability, gateway-api-manifests).
cd "$HOME"
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"
git sparse-checkout add argocd 2>/dev/null || git sparse-checkout set argocd
git sparse-checkout add observability 2>/dev/null || true
git sparse-checkout add gateway-api-manifests 2>/dev/null || true
git pull

# -------------------------------------------------------
# Reverse step 10: Grafana and Prometheus routes
# Removes HTTPRoutes and TargetGroupConfigurations from expose-grafana-prometheus.sh.
# External DNS must still be running so grafana/prometheus DNS records are cleaned.
# -------------------------------------------------------
echo "Reverse step 10: Delete Grafana/Prometheus routes"
echo ""

kubectl delete -f "$GRAFANA_ROUTE" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
kubectl delete -f "$GRAFANA_TG" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "httproute/grafana-route" "monitoring" "120s"
wait_for_delete "targetgroupconfiguration/grafana-tg-config" "monitoring" "120s"

kubectl delete -f "$PROMETHEUS_ROUTE" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
kubectl delete -f "$PROMETHEUS_TG" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "httproute/prometheus-route" "monitoring" "120s"
wait_for_delete "targetgroupconfiguration/prometheus-tg-config" "monitoring" "120s"

wait_for_external_dns_cleanup 60

echo "Grafana/Prometheus routes removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 9: kube-prometheus-stack
# Uninstalls the Helm release from install-kube-prometheus-stack.sh, then the namespace.
# -------------------------------------------------------
echo "Reverse step 9: Delete kube-prometheus-stack"
echo ""

helm_uninstall_and_wait "kube-prometheus-stack" "monitoring" "kube-prometheus-stack-grafana" "300s"

echo "Waiting for monitoring workloads to terminate..."
kubectl wait --for=delete pod --all -n monitoring --timeout=300s 2>/dev/null || true

kubectl delete namespace monitoring --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/monitoring" "" "600s"

echo "kube-prometheus-stack removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 8: Boutique app
# Removes the Argo CD Application from apply-boutique-app.sh and its namespace.
# External DNS must still be running so app.oliver14.com is cleaned later.
# -------------------------------------------------------
echo "Reverse step 8: Delete boutique app"
echo ""

kubectl delete -f "$BOUTIQUE_APP_CR" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
kubectl delete application boutique-app -n argocd --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "application/boutique-app" "argocd" "180s"

echo "Waiting for boutique-app workloads to terminate..."
kubectl wait --for=delete pod --all -n boutique-app --timeout=300s 2>/dev/null || true

kubectl delete namespace boutique-app --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/boutique-app" "" "600s"

echo "Boutique app removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 7: Argo CD Image Updater
# Removes the image updater installed by install-argocd-image-updater.sh.
# -------------------------------------------------------
echo "Reverse step 7: Delete Argo CD Image Updater"
echo ""

kubectl delete -f "$IMAGE_UPDATER_CR" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "imageupdater/boutique-image-updater" "argocd" "120s"

helm_uninstall_and_wait "argocd-image-updater" "argocd" "argocd-image-updater-controller" "180s"

kubectl delete crd imageupdaters.argocd-image-updater.argoproj.io --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true

echo "Argo CD Image Updater removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 6: Argo CD
# Detaches the ALB target group, uninstalls Argo CD, and deletes its namespace and CRDs.
# External DNS still running — cleans argocd.oliver14.com when the HTTPRoute is removed.
# -------------------------------------------------------
echo "Reverse step 6: Delete ArgoCD"
echo ""

kubectl delete -f "$ARGOCD_TARGET_GRP" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "targetgroupconfiguration/argo-tg-config" "argocd" "120s"

helm_uninstall_and_wait "argo-cd" "argocd" "argo-cd-argocd-server" "180s"

kubectl delete namespace argocd --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/argocd" "" "600s"

kubectl delete crd \
  applications.argoproj.io \
  applicationsets.argoproj.io \
  appprojects.argoproj.io \
  --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true

wait_for_external_dns_cleanup 90

echo "ArgoCD removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 5: Gateway / ALB
# Deletes the shared ALB Gateway from apply-gateway-manifests.sh.
# Gateway deletion removes the internet-facing load balancer (can take several minutes).
# -------------------------------------------------------
echo "Reverse step 5: Delete gateway manifests"
echo ""

kubectl delete httproute --all -A --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

kubectl delete -f "$MANIFESTS_DIR/gateway.yaml" --ignore-not-found --wait=true --timeout=600s 2>/dev/null || true
wait_for_delete "gateway/app-alb-gateway" "default" "600s"

kubectl delete -f "$MANIFESTS_DIR/alb-config.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "loadbalancerconfiguration/app-gw-lbconfig" "default" "120s"

kubectl delete -f "$MANIFESTS_DIR/gateway-class.yaml" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "gatewayclass/aws-alb-gateway-class" "" "120s"

wait_for_external_dns_cleanup 120

echo "Gateway manifests removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 4: External DNS
# Safe to remove once HTTPRoutes and the Gateway are gone.
# -------------------------------------------------------
echo "Reverse step 4: Delete External DNS"
echo ""

helm_uninstall_and_wait "external-dns" "external-dns" "external-dns" "180s"

kubectl delete namespace external-dns --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/external-dns" "" "600s"

kubectl delete crd dnsendpoints.externaldns.k8s.io --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true

# Revoke Route53 permissions from the external-dns service account.
echo "Revoking External DNS Pod Identity association..."
eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" 2>/dev/null \
  && echo "Pod Identity association removed." \
  || echo "WARNING: Pod Identity association not found or could not be deleted."

cleanup_orphan_route53_records

echo "External DNS removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 4: Gateway API CRDs
# Remove custom resource definitions once all Gateway objects are gone.
# -------------------------------------------------------
echo "Reverse step 4: Delete Gateway API CRDs"
echo ""

kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

echo "Gateway API CRDs removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 3: AWS Load Balancer Controller
# Uninstalls the controller from install-lbc.sh and revokes its IAM service account.
# -------------------------------------------------------
echo "Reverse step 3: Delete AWS Load Balancer Controller"
echo ""

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
wait_for_delete "deployment/aws-load-balancer-controller" "kube-system" "600s"

echo "Revoking LBC IAM service account..."
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region="$REGION" 2>/dev/null \
  && echo "LBC IAM service account removed." \
  || echo "WARNING: LBC IAM service account not found or could not be deleted."

kubectl delete -f https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

echo "NOTE: priorityclass/system-cluster-critical may remain (Kubernetes system resource)."
echo "Load Balancer Controller removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Reverse step 2: Cluster Autoscaler
# Uninstalls the controller from install-cluster-autoscaler.sh and revokes its IAM service account.
# -------------------------------------------------------
echo "Reverse step 2: Delete Cluster Autoscaler"
echo ""

helm uninstall cluster-autoscaler -n kube-system 2>/dev/null || true
wait_for_delete "deployment/cluster-autoscaler-aws-cluster-autoscaler" "kube-system" "180s"

echo "Revoking Cluster Autoscaler IAM service account..."
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --region="$REGION" 2>/dev/null \
  && echo "Cluster Autoscaler IAM service account removed." \
  || echo "WARNING: Cluster Autoscaler IAM service account not found or could not be deleted."

echo "Cluster Autoscaler removed."
echo ""
echo "----------------------------------------"
echo ""

# Reverse step 1: configure-kubeconfig — no cluster resources to delete.
echo "Reverse step 1: configure-kubeconfig (no cluster resources to delete)"
echo ""
echo "NOTE: Node ENIs will clear when you destroy the EKS cluster."

echo ""
echo "========================================"
echo "  Kubernetes teardown finished"
echo "========================================"
echo ""
echo "Next: terraform destroy in 03_eks, then 02_bastion, then 01_vpc"
echo ""
