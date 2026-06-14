#!/bin/bash
set -euo pipefail

# Tear down everything installed by run-setup.sh + manual steps, in reverse order.
# Run BEFORE: terraform destroy (03_eks → 02_bastion → 01_vpc)
#
# Usage: /opt/bastion/delete-kubernetes-workloads.sh

REGION="us-east-1"
CLUSTER_NAME="terraform-cluster"
DNS_DOMAIN="oliver14.com"
GITHUB_REPO_URL="https://github.com/oliversims/Production-Grade_GitOps-Driven_Microservices.git"

REPO_DIR="$HOME/Production-Grade_GitOps-Driven_Microservices"
MANIFESTS_DIR="$REPO_DIR/gateway-api-manifests"
ARGOCD_TARGET_GRP="$REPO_DIR/argocd/target-grp-config.yaml"
IMAGE_UPDATER_CR="$REPO_DIR/argocd/image-updater.yaml"
BOUTIQUE_APP_CR="$REPO_DIR/argocd/argocd-apps/boutique-app.yaml"

# Poll until a resource is gone. Skips if already deleted. Default timeout: 3 min.
wait_for_delete() {
  local resource="$1"
  local namespace="${2:-}"
  local timeout="${3:-180s}"

  kubectl get ${namespace:+-n "$namespace"} "$resource" >/dev/null 2>&1 || {
    echo "$resource already gone."
    return
  }

  echo "Waiting for $resource to be fully removed..."
  kubectl wait ${namespace:+-n "$namespace"} --for=delete "$resource" --timeout="$timeout" \
    || echo "WARNING: Timed out waiting for $resource to be deleted."
}

# helm uninstall + wait for its deployment to disappear.
helm_uninstall_and_wait() {
  local release="$1"
  local namespace="$2"
  local deployment="$3"
  local timeout="${4:-180s}"

  helm uninstall "$release" -n "$namespace" 2>/dev/null || true
  wait_for_delete "deployment/$deployment" "$namespace" "$timeout"
}

# True while app/argocd (or External DNS ownership TXT) records still exist in Route53.
route53_app_argocd_records_exist() {
  local zone_id
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$DNS_DOMAIN" \
    --query "HostedZones[?Name=='${DNS_DOMAIN}.'].Id" --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')
  [ -n "$zone_id" ] || return 1

  aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --output json 2>/dev/null \
    | python3 -c "
import json, sys
names = {
    'app.${DNS_DOMAIN}.', 'argocd.${DNS_DOMAIN}.',
    'aaaa-app.${DNS_DOMAIN}.', 'aaaa-argocd.${DNS_DOMAIN}.',
    'cname-app.${DNS_DOMAIN}.', 'cname-argocd.${DNS_DOMAIN}.',
}
records = json.load(sys.stdin).get('ResourceRecordSets', [])
sys.exit(0 if any(r['Name'] in names for r in records) else 1)
"
}

# Poll Route53 while External DNS is running; fall back to a short sleep if AWS API is unavailable.
wait_for_external_dns_cleanup() {
  local seconds="${1:-120}"
  if ! kubectl get deployment/external-dns -n external-dns >/dev/null 2>&1; then
    echo "External DNS not running — Route53 fallback will run after step 4."
    return
  fi

  echo "Waiting up to ${seconds}s for External DNS to remove app/argocd Route53 records..."
  local elapsed=0
  while [ "$elapsed" -lt "$seconds" ]; do
    if ! route53_app_argocd_records_exist; then
      echo "Route53 records for app/argocd removed."
      return
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "WARNING: Timed out waiting for External DNS Route53 cleanup — fallback will run after step 4."
}

# Safety net: delete any remaining app/argocd records (handles slow reconcile or External DNS already gone).
cleanup_orphan_route53_records() {
  echo "Checking Route53 for orphaned app/argocd records..."
  python3 <<PY
import json
import subprocess
import sys

DOMAIN = "${DNS_DOMAIN}"
MANAGED_NAMES = {
    f"app.{DOMAIN}.",
    f"argocd.{DOMAIN}.",
    f"aaaa-app.{DOMAIN}.",
    f"aaaa-argocd.{DOMAIN}.",
    f"cname-app.{DOMAIN}.",
    f"cname-argocd.{DOMAIN}.",
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
echo "  (reverse of setup: step 8 → 1)"
echo "========================================"
echo ""

# Connect kubectl to the EKS cluster.
/opt/bastion/configure-kubeconfig.sh

# Pull delete manifests from GitHub (argocd + gateway-api-manifests folders).
cd "$HOME"
git clone --filter=blob:none --sparse -b main "$GITHUB_REPO_URL" 2>/dev/null || true
cd "$REPO_DIR"
git sparse-checkout add argocd 2>/dev/null || git sparse-checkout set argocd
git sparse-checkout add gateway-api-manifests 2>/dev/null || true
git pull

# -------------------------------------------------------
# Step 8 (reverse): Boutique app (manual apply-boutique-app.sh)
# Remove Argo CD Application, workloads, then namespace.
# External DNS must still be running so app.oliver14.com is cleaned later.
# -------------------------------------------------------
echo "Reverse step 8: Delete boutique app"
echo ""

kubectl delete -f "$BOUTIQUE_APP_CR" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
kubectl delete application boutique-app -n argocd --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
wait_for_delete "application/boutique-app" "argocd" "180s"

# Wait for boutique workloads to drain before deleting the namespace.
if kubectl get namespace boutique-app >/dev/null 2>&1; then
  echo "Waiting for boutique-app workloads to terminate..."
  kubectl wait --for=delete pod --all -n boutique-app --timeout=300s 2>/dev/null || true
fi

kubectl delete namespace boutique-app --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/boutique-app" "" "600s"

echo "Boutique app removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 7 (reverse): Argo CD Image Updater
# Watches GHCR for new images — remove before Argo CD itself.
# -------------------------------------------------------
echo "Reverse step 7: Delete Argo CD Image Updater"
echo ""

kubectl delete -f "$IMAGE_UPDATER_CR" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "imageupdater/boutique-image-updater" "argocd" "120s"

helm_uninstall_and_wait "argocd-image-updater" "argocd" "argocd-image-updater-controller" 180s

kubectl delete crd imageupdaters.argocd-image-updater.argoproj.io --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true

echo "Argo CD Image Updater removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 6 (reverse): Argo CD
# Detach from ALB, uninstall Helm (removes argocd HTTPRoute), delete namespace + CRDs.
# External DNS still running — cleans argocd.oliver14.com when HTTPRoute is removed.
# -------------------------------------------------------
echo "Reverse step 6: Delete ArgoCD"
echo ""

kubectl delete -f "$ARGOCD_TARGET_GRP" --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true
wait_for_delete "targetgroupconfiguration/argo-tg-config" "argocd" "120s"

helm_uninstall_and_wait "argo-cd" "argocd" "argo-cd-argocd-server" 180s

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
# Step 5 (reverse): Gateway / ALB
# Delete HTTPRoutes and Gateway while External DNS is still running.
# External DNS removes app.oliver14.com records; Gateway deletion removes the ALB.
# -------------------------------------------------------
echo "Reverse step 5: Delete gateway manifests"
echo ""

kubectl delete httproute --all -A --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

# Deleting the Gateway tells AWS to remove the internet-facing ALB (slow — up to 10 min).
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
# Step 4 (reverse): External DNS
# Safe to remove once all HTTPRoutes/Gateways are gone and Route53 has reconciled.
# -------------------------------------------------------
echo "Reverse step 4: Delete External DNS"
echo ""

helm_uninstall_and_wait "external-dns" "external-dns" "external-dns" 180s

kubectl delete namespace external-dns --ignore-not-found --wait=true --timeout=180s
wait_for_delete "namespace/external-dns" "" "600s"

kubectl delete crd dnsendpoints.externaldns.k8s.io --ignore-not-found --wait=true --timeout=60s 2>/dev/null || true

# Revoke AWS Pod Identity (Route53 permissions). Run after namespace delete — association is cluster-scoped.
echo "Revoking External DNS Pod Identity association..."
if eksctl delete podidentityassociation \
  --cluster="$CLUSTER_NAME" \
  --namespace=external-dns \
  --service-account-name=external-dns \
  --region="$REGION" 2>/dev/null; then
  echo "Pod Identity association removed."
else
  echo "WARNING: Pod Identity association not found or could not be deleted."
  echo "         Check: eksctl get podidentityassociation --cluster=$CLUSTER_NAME --region=$REGION"
fi

cleanup_orphan_route53_records

echo "External DNS removed."
echo ""
echo "----------------------------------------"
echo ""

# -------------------------------------------------------
# Step 3 (reverse): Gateway API CRDs
# Custom resource definitions — safe to remove once all Gateway objects are gone.
# -------------------------------------------------------
echo "Reverse step 3: Delete Gateway API CRDs"
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
# Step 2 (reverse): AWS Load Balancer Controller
# Controller that manages ALBs — remove last among platform components.
# -------------------------------------------------------
echo "Reverse step 2: Delete AWS Load Balancer Controller"
echo ""

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
wait_for_delete "deployment/aws-load-balancer-controller" "kube-system" "600s"

# Revoke IAM role (IRSA) used by the controller.
echo "Revoking LBC IAM service account..."
if eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region="$REGION" 2>/dev/null; then
  echo "LBC IAM service account removed."
else
  echo "WARNING: LBC IAM service account not found or could not be deleted."
fi

kubectl delete -f https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml \
  --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

# system-cluster-critical is marked as a system PriorityClass and cannot be deleted.
echo "NOTE: priorityclass/system-cluster-critical may remain (Kubernetes forbids deleting system priority classes)."

echo "Load Balancer Controller removed."
echo ""
echo "----------------------------------------"
echo ""

# Step 1 (reverse): configure-kubeconfig — no resources to delete.
echo "Reverse step 1: configure-kubeconfig (no cluster resources to delete)"
echo ""

# Node ENIs stay until the EKS cluster itself is destroyed.
echo "NOTE: Node ENIs will clear when you destroy the EKS cluster."
echo "NOTE: priorityclass/system-cluster-critical may remain (Kubernetes system resource)."

echo ""
echo "========================================"
echo "  Kubernetes teardown finished"
echo "========================================"
echo ""
echo "Next: terraform destroy in 03_eks, then 02_bastion, then 01_vpc"
echo ""
