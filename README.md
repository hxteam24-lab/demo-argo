# GitOps Demo - GitLab CE + Argo CD + Helm + Image Updater

## Architecture

```
demo_final/
├── charts/                  # Local Helm charts
│   ├── adguard/
│   ├── homeassistant/
│   ├── nextcloud/
│   └── gitlab/              ← GitLab CE (runs in-cluster)
├── values/                  # Value overrides (edit these!)
│   ├── adguard-values.yaml
│   ├── homeassistant-values.yaml
│   └── nextcloud-values.yaml
├── argocd/                  # Argo CD Application definitions
│   ├── adguard-app.yaml
│   ├── homeassistant-app.yaml
│   └── nextcloud-app.yaml
└── setup.sh                 # One-click install script
```

## Flow

```
GitLab CE (in-cluster, gitlab namespace)
    ↓  Argo CD watches repo
Argo CD (argocd namespace)
    ↓  Deploys Helm charts
Applications (adguard / homeassistant / nextcloud namespaces)
    ↑
Argo CD Image Updater
    ↑  Watches Docker registries, commits tag updates to GitLab
```

## Prerequisites

- kubeadm cluster running
- `kubectl` configured
- `helm` installed

## Quick Start

### 1. Run the setup script

```bash
cd demo_final
chmod +x setup.sh
./setup.sh
```

This will:
- Deploy GitLab CE in the `gitlab` namespace
- Install Argo CD + Image Updater in `argocd` namespace
- Register the internal GitLab repo in Argo CD
- Deploy all three application definitions

### 2. Access GitLab and create the repo

```bash
kubectl port-forward svc/gitlab -n gitlab 8929:80
```

Open http://localhost:8929, login:
- **Username:** root
- **Password:** Demo1234!

Create a new project called `demo-gitops` (blank, no README).

### 3. Push this code to GitLab

```bash
git init
git remote add origin http://localhost:8929/root/demo-gitops.git
git add .
git commit -m "initial gitops setup"
git push -u origin main
# Username: root / Password: Demo1234!
```

### 4. Access Argo CD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 (accept self-signed cert).
The password is printed by `setup.sh`, or retrieve it:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Managing Applications

### Change image tag

Edit `values/adguard-values.yaml`:
```yaml
image:
  tag: v0.107.53   # <-- change this
```

Commit and push to GitLab. Argo CD will detect the change and roll the deployment automatically.

### Change replicas

Edit `values/homeassistant-values.yaml`:
```yaml
replicaCount: 3   # <-- scale up
```

Commit and push to GitLab.

### Change resources

Edit any values file:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

## Automatic Image Updates (Image Updater)

The Argo CD Image Updater watches Docker registries and automatically updates image tags.

Configured strategies:
- **AdGuard**: `semver` - picks latest semantic version tag
- **Home Assistant**: `latest` - follows the `stable` tag
- **Nextcloud**: `semver` - picks latest semantic version tag

When a new image is published, Image Updater will:
1. Detect the new tag
2. Commit the change to your Git repo (or patch the app directly)
3. Argo CD syncs the change
4. Pods roll automatically

### Configure write-back method

In the `argocd/*.yaml` files, the annotation:
```yaml
argocd-image-updater.argoproj.io/write-back-method: git
```

Options:
- `git` - commits tag changes back to your Git repo (recommended)
- `argocd` - patches the Application directly (no Git commit)

For `git` write-back, the setup script already creates the `git-creds` secret
pointing to your internal GitLab. No external GitHub token needed.

## Useful Commands

```bash
# Check all Argo CD applications
kubectl get applications -n argocd

# Watch pods across all namespaces
kubectl get pods -A -w

# Check Image Updater logs
kubectl logs -n argocd deployment/argocd-image-updater

# Force sync an application
kubectl -n argocd patch application adguard --type merge -p '{"operation":{"sync":{}}}'

# Access GitLab
kubectl port-forward svc/gitlab -n gitlab 8929:80

# Access AdGuard (initial setup on port 3000)
kubectl port-forward svc/adguard -n adguard 3000:3000

# Access Home Assistant
kubectl port-forward svc/homeassistant -n homeassistant 8123:8123

# Access Nextcloud
kubectl port-forward svc/nextcloud -n nextcloud 8888:80
```

## Demo Flow

1. Run `setup.sh` → GitLab + Argo CD deploy
2. Port-forward GitLab, create repo, push code
3. Open Argo CD UI → show apps synced & healthy
4. Edit a values file (change tag or replicas)
5. `git commit && git push` to internal GitLab
6. Watch Argo CD detect drift and auto-sync
7. Show pods rolling out with `kubectl get pods -w`
8. (Bonus) Show Image Updater auto-detecting a new tag and committing to GitLab
