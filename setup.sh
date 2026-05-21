#!/bin/bash
set -e

GITHUB_REPO="https://github.com/hxteam24-lab/demo-argo.git"

echo "============================================"
echo "  GitOps Demo Setup Script"
echo "  GitHub + Argo CD"
echo "  For kubeadm clusters with Helm"
echo "============================================"
echo ""

# -----------------------------------------------
# Step 1: Prerequisites
# -----------------------------------------------
echo "[1/5] Setting up storage provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml

echo "Waiting for ingress controller to be ready..."
kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s

echo "Patching ingress controller to use NodePort 30080..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  --type='json' -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

echo "Enabling configuration-snippet in ingress controller..."
kubectl set env deployment/ingress-nginx-controller -n ingress-nginx \
  NGINX_INGRESS_CONTROLLER_ARGS="--enable-annotation-validation=false" || true
kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
  --type merge -p '{"data":{"allow-snippet-annotations":"true"}}'

# -----------------------------------------------
# Step 2: Install Argo CD
# -----------------------------------------------
echo "[2/5] Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Installing Argo CD..."
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# -----------------------------------------------
# Step 3: Get Argo CD admin password
# -----------------------------------------------
echo "[4/5] Retrieving Argo CD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "  Argo CD Admin Credentials:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""

# -----------------------------------------------
# Step 4: Deploy the applications
# -----------------------------------------------
echo "[5/5] Deploying Argo CD Applications..."
kubectl apply -f argocd/

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "To access Argo CD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo ""
echo "To check application status:"
echo "  kubectl get applications -n argocd"
echo ""
echo "To watch pods rolling out:"
echo "  kubectl get pods -A -w"
echo ""
