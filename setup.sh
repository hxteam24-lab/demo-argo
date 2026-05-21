#!/bin/bash
set -e

GITLAB_URL="http://gitlab.gitlab.svc.cluster.local"
GITLAB_REPO="root/demo-gitops"
GITLAB_USER="root"
GITLAB_PASS="Demo1234!"

echo "============================================"
echo "  GitOps Demo Setup Script"
echo "  GitLab CE + Argo CD + Image Updater"
echo "  For kubeadm clusters with Helm"
echo "============================================"
echo ""

# -----------------------------------------------
# Step 1: Deploy GitLab CE
# -----------------------------------------------
echo "[1/7] Creating gitlab namespace..."
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "[2/7] Installing GitLab CE via Helm..."
helm upgrade --install gitlab charts/gitlab \
  --namespace gitlab \
  --wait --timeout 10m

echo "Waiting for GitLab to become ready (this takes a few minutes)..."
kubectl wait --for=condition=available deployment/gitlab -n gitlab --timeout=600s

echo ""
echo "  GitLab CE Credentials:"
echo "  URL: $GITLAB_URL (internal) or use port-forward"
echo "  Username: $GITLAB_USER"
echo "  Password: $GITLAB_PASS"
echo ""

# -----------------------------------------------
# Step 2: Install Argo CD
# -----------------------------------------------
echo "[3/7] Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "[4/7] Installing Argo CD..."
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# -----------------------------------------------
# Step 3: Install Argo CD Image Updater
# -----------------------------------------------
echo "[5/7] Installing Argo CD Image Updater..."
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

echo "Waiting for Image Updater to be ready..."
kubectl wait --for=condition=available deployment/argocd-image-updater -n argocd --timeout=120s

# -----------------------------------------------
# Step 4: Get Argo CD admin password
# -----------------------------------------------
echo "[6/7] Retrieving Argo CD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "  Argo CD Admin Credentials:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""

# -----------------------------------------------
# Step 5: Register GitLab repo in Argo CD
# -----------------------------------------------
echo "Configuring Argo CD to connect to internal GitLab..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: ${GITLAB_URL}
  username: ${GITLAB_USER}
  password: ${GITLAB_PASS}
---
apiVersion: v1
kind: Secret
metadata:
  name: demo-gitops-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${GITLAB_URL}/${GITLAB_REPO}.git
  username: ${GITLAB_USER}
  password: ${GITLAB_PASS}
  insecure: "true"
EOF

# Configure Image Updater git credentials for write-back
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: git-creds
  namespace: argocd
stringData:
  username: ${GITLAB_USER}
  password: ${GITLAB_PASS}
EOF

# -----------------------------------------------
# Step 6: Deploy the applications
# -----------------------------------------------
echo "[7/7] Deploying Argo CD Applications..."
kubectl apply -f argocd/

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "IMPORTANT: Before Argo CD can sync, you must:"
echo "  1. Access GitLab and create the project '$GITLAB_REPO'"
echo "  2. Push this repo content to GitLab"
echo ""
echo "  Quick steps:"
echo "    kubectl port-forward svc/gitlab -n gitlab 8929:80"
echo "    # Open http://localhost:8929, login as root/Demo1234!"
echo "    # Create project 'demo-gitops' (no README)"
echo ""
echo "    git init && git remote add origin http://localhost:8929/${GITLAB_REPO}.git"
echo "    git add . && git commit -m 'initial gitops setup'"
echo "    git push -u origin main"
echo ""
echo "To access Argo CD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo ""
echo "To access GitLab UI:"
echo "  kubectl port-forward svc/gitlab -n gitlab 8929:80"
echo "  Then open: http://localhost:8929"
echo ""
echo "To check application status:"
echo "  kubectl get applications -n argocd"
echo ""
echo "To watch pods rolling out:"
echo "  kubectl get pods -A -w"
echo ""
