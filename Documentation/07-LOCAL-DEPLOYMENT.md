# Local Deployment Instructions

## Complete Guide to Running the Embassy Appointment System Locally with KIND

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Quick Start (5 minutes)](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Testing the Application](#testing-the-application)
5. [Troubleshooting](#troubleshooting)
6. [Cleanup](#cleanup)

---

## Prerequisites

### Required Software

#### 1. Docker Desktop
- **Windows**: [Download Docker Desktop](https://www.docker.com/products/docker-desktop)
- **Mac**: [Download Docker Desktop](https://www.docker.com/products/docker-desktop)
- **Linux**: [Install Docker Engine](https://docs.docker.com/engine/install/)

**Verify Installation**:
```powershell
docker --version
# Expected: Docker version 24.0.0 or higher
```

#### 2. kubectl (Kubernetes CLI)
**Windows (PowerShell as Administrator)**:
```powershell
# Using Chocolatey
choco install kubernetes-cli

# Or download manually
curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
Move-Item kubectl.exe C:\Windows\System32\
```

**Mac**:
```bash
brew install kubectl
```

**Linux**:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Verify**:
```powershell
kubectl version --client
```

#### 3. KIND (Kubernetes IN Docker)
**Windows (PowerShell as Administrator)**:
```powershell
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item kind-windows-amd64.exe C:\Windows\System32\kind.exe
```

**Mac**:
```bash
brew install kind
```

**Linux**:
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

**Verify**:
```powershell
kind --version
# Expected: kind v0.20.0 or higher
```

#### 4. Helm
**Windows (PowerShell as Administrator)**:
```powershell
choco install kubernetes-helm
```

**Mac**:
```bash
brew install helm
```

**Linux**:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify**:
```powershell
helm version
# Expected: version.BuildInfo{Version:"v3.12.0" or higher}
```

---

## Quick Start (5 Minutes)

### For Windows Users

1. **Open PowerShell as Administrator**

2. **Navigate to project directory**:
```powershell
cd "C:\Users\sinad\VS Code\appointment_app"
```

3. **Run setup script**:
```powershell
.\setup-kind.ps1
```

4. **Deploy application**:
```powershell
helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments
```

5. **Wait for pods to be ready** (30-60 seconds):
```powershell
kubectl get pods -n embassy-appointments -w
# Press Ctrl+C when all pods show "Running" and "1/1" ready
```

6. **Access application**:
- Open browser: http://appointments.local
- Or use port-forward: 
```powershell
kubectl port-forward svc/appointments-embassy-appointments 8080:80 -n embassy-appointments
# Then open: http://localhost:8080
```

---

## Detailed Setup

### Step 1: Verify Prerequisites

```powershell
# Check Docker
docker ps
# Should show running containers (or empty table if none)

# Check kubectl
kubectl version --client

# Check KIND
kind version

# Check Helm
helm version
```

If any command fails, install the missing prerequisite from above.

---

### Step 2: Create KIND Cluster

```powershell
# Create cluster with custom configuration
kind create cluster --config kind-config.yaml --wait 5m

# Expected output:
# Creating cluster "embassy-appointments" ...
# ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
# ✓ Preparing nodes 📦 📦 📦
# ✓ Writing configuration 📜
# ✓ Starting control-plane 🕹️
# ✓ Installing CNI 🔌
# ✓ Installing StorageClass 💾
# ✓ Joining worker nodes 🚜
# Set kubectl context to "kind-embassy-appointments"
```

**Verify cluster**:
```powershell
kubectl cluster-info --context kind-embassy-appointments

kubectl get nodes
# Should show 1 control-plane and 2 worker nodes
```

---

### Step 3: Install NGINX Ingress Controller

```powershell
# Apply NGINX Ingress manifest
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

# Verify
kubectl get pods -n ingress-nginx
# NAME                                        READY   STATUS    RESTARTS   AGE
# ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

---

### Step 4: Install Metrics Server (for HPA)

```powershell
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for KIND (insecure TLS)
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait for ready
kubectl wait --namespace kube-system `
  --for=condition=ready pod `
  --selector=k8s-app=metrics-server `
  --timeout=300s

# Verify
kubectl top nodes
# Should show CPU and memory usage
```

---

### Step 5: Build and Load Docker Image

```powershell
# Build Docker image
docker build -t embassy-appointments:latest .

# Expected output:
# [+] Building 45.2s (12/12) FINISHED
# ...
# => => naming to docker.io/library/embassy-appointments:latest

# Load image into KIND cluster
kind load docker-image embassy-appointments:latest --name embassy-appointments

# Verify
docker exec -it embassy-appointments-control-plane crictl images | Select-String "embassy"
```

---

### Step 6: Update Hosts File

**Windows**:
```powershell
# Run as Administrator
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n127.0.0.1 appointments.local"
```

**Mac/Linux**:
```bash
echo "127.0.0.1 appointments.local" | sudo tee -a /etc/hosts
```

**Verify**:
```powershell
ping appointments.local
# Should resolve to 127.0.0.1
```

---

### Step 7: Create Namespace

```powershell
kubectl create namespace embassy-appointments

# Verify
kubectl get namespaces
# Should show embassy-appointments
```

---

### Step 8: Deploy Application with Helm

```powershell
# Install chart
helm install appointments ./helm-chart `
  -f helm-chart/values-dev.yaml `
  -n embassy-appointments

# Expected output:
# NAME: appointments
# LAST DEPLOYED: Thu Dec  5 15:30:00 2025
# NAMESPACE: embassy-appointments
# STATUS: deployed
# REVISION: 1

# Check deployment status
helm status appointments -n embassy-appointments
```

---

### Step 9: Wait for Pods to be Ready

```powershell
# Watch pod status
kubectl get pods -n embassy-appointments -w

# Expected output (after 30-60 seconds):
# NAME                                                  READY   STATUS    RESTARTS   AGE
# appointments-embassy-appointments-xxxxxxxxxx-xxxxx    1/1     Running   0          1m

# Press Ctrl+C to stop watching

# Check all resources
kubectl get all -n embassy-appointments
```

---

## Testing the Application

### 1. Access via Ingress (Recommended)

**Open browser**: http://appointments.local

If you see the appointment scheduling page, **SUCCESS!** 🎉

---

### 2. Access via Port Forward (Alternative)

```powershell
kubectl port-forward svc/appointments-embassy-appointments 8080:80 -n embassy-appointments

# Keep terminal open, in another terminal or browser:
# http://localhost:8080
```

---

### 3. Test Health Endpoints

**Health Check**:
```powershell
curl http://appointments.local/health

# Expected response:
# {"status":"healthy","timestamp":"2025-12-05T15:30:00.000000","version":"1.0.0","environment":"development"}
```

**Readiness Check**:
```powershell
curl http://appointments.local/ready

# Expected response:
# {"status":"ready","timestamp":"2025-12-05T15:30:00.000000"}
```

**Metrics**:
```powershell
curl http://appointments.local/metrics

# Expected response (Prometheus format):
# # HELP appointments_total Total number of appointments
# # TYPE appointments_total counter
# appointments_total 0
# ...
```

---

### 4. Create Test Appointment

1. **Navigate to**: http://appointments.local
2. **Fill out form**:
   - Full Name: John Doe
   - Email: john.doe@example.com
   - Passport Number: AB123456
   - Medical Exam Date: (select a recent date)
   - Appointment Date: (select a future date)
   - Appointment Time: 10:00 AM
3. **Click "Schedule Appointment"**
4. **Verify**: You should see a confirmation page with appointment details

---

### 5. View Appointments

- **Navigate to**: http://appointments.local/appointments
- **Verify**: Your test appointment appears in the list

---

### 6. View Logs

```powershell
# Get pod name
$POD_NAME = kubectl get pods -n embassy-appointments -l "app.kubernetes.io/name=embassy-appointments" -o jsonpath="{.items[0].metadata.name}"

# View logs
kubectl logs $POD_NAME -n embassy-appointments

# Follow logs (live)
kubectl logs -f $POD_NAME -n embassy-appointments
```

---

### 7. Check Auto-Scaling (HPA)

```powershell
# View HPA status
kubectl get hpa -n embassy-appointments

# Expected output:
# NAME                            REFERENCE                                  TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# appointments-embassy-appoint... Deployment/appointments-embassy-appoint... 5%/70%          3         10        3          5m

# Note: HPA is disabled in values-dev.yaml, to enable:
# helm upgrade appointments ./helm-chart -f helm-chart/values-dev.yaml --set autoscaling.enabled=true -n embassy-appointments
```

---

## Troubleshooting

### Issue 1: Pods Not Starting

**Check pod status**:
```powershell
kubectl describe pod <pod-name> -n embassy-appointments
```

**Common causes**:
- Image not loaded: `kind load docker-image embassy-appointments:latest --name embassy-appointments`
- Insufficient resources: Increase Docker Desktop resources (Settings → Resources)
- Image pull errors: Verify image name in values-dev.yaml matches built image

---

### Issue 2: Ingress Not Working

**Check ingress status**:
```powershell
kubectl get ingress -n embassy-appointments
kubectl describe ingress -n embassy-appointments
```

**Check ingress controller**:
```powershell
kubectl get pods -n ingress-nginx
```

**Common causes**:
- Ingress controller not ready: Wait or reinstall
- Hosts file not updated: Verify `C:\Windows\System32\drivers\etc\hosts`
- Port 80 in use: Check with `netstat -ano | findstr :80` and close conflicting process

---

### Issue 3: Cannot Access appointments.local

**Use port-forward**:
```powershell
kubectl port-forward svc/appointments-embassy-appointments 8080:80 -n embassy-appointments
# Access: http://localhost:8080
```

**Check DNS resolution**:
```powershell
nslookup appointments.local
# Should show 127.0.0.1
```

**Try IP directly**:
```powershell
# Get service IP
kubectl get svc -n embassy-appointments

# Access via NodePort (if configured)
# http://localhost:30080
```

---

### Issue 4: Database Errors

**Check logs**:
```powershell
kubectl logs <pod-name> -n embassy-appointments
```

**Common causes**:
- Persistent volume not created: Check `kubectl get pvc -n embassy-appointments`
- Permissions issue: Pods run as non-root, check SecurityContext
- Database locked: Restart pod with `kubectl delete pod <pod-name> -n embassy-appointments`

---

### Issue 5: Metrics Server Not Working

**Check status**:
```powershell
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

**Verify patch**:
```powershell
kubectl get deployment metrics-server -n kube-system -o yaml | Select-String "kubelet-insecure-tls"
```

**Re-apply if needed**:
```powershell
kubectl delete deployment metrics-server -n kube-system
# Then re-install from Step 4
```

---

## Useful Commands

### View Resources
```powershell
# All resources in namespace
kubectl get all -n embassy-appointments

# Detailed pod info
kubectl describe pod <pod-name> -n embassy-appointments

# Service endpoints
kubectl get endpoints -n embassy-appointments

# ConfigMap content
kubectl get configmap appointments-embassy-appointments -n embassy-appointments -o yaml

# Secret (base64 encoded)
kubectl get secret appointments-embassy-appointments -n embassy-appointments -o yaml
```

### Debugging
```powershell
# Execute command in pod
kubectl exec -it <pod-name> -n embassy-appointments -- /bin/sh

# Copy database out of pod
kubectl cp embassy-appointments/<pod-name>:/app/data/appointments.db ./appointments-backup.db

# Check events
kubectl get events -n embassy-appointments --sort-by='.lastTimestamp'
```

### Helm Operations
```powershell
# List releases
helm list -n embassy-appointments

# View values
helm get values appointments -n embassy-appointments

# Upgrade release
helm upgrade appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments

# Rollback
helm rollback appointments 1 -n embassy-appointments

# Uninstall
helm uninstall appointments -n embassy-appointments
```

---

## Cleanup

### Remove Application
```powershell
# Uninstall Helm release
helm uninstall appointments -n embassy-appointments

# Delete namespace
kubectl delete namespace embassy-appointments
```

### Delete KIND Cluster
```powershell
kind delete cluster --name embassy-appointments
```

### Remove Docker Image
```powershell
docker rmi embassy-appointments:latest
```

### Clean Up Hosts File
**Windows**: Edit `C:\Windows\System32\drivers\etc\hosts` and remove line with `appointments.local`

---

## Advanced: Multi-Environment Setup

### Running Dev and Staging Simultaneously

```powershell
# Deploy to dev namespace
helm install appointments-dev ./helm-chart `
  -f helm-chart/values-dev.yaml `
  -n embassy-dev --create-namespace `
  --set ingress.hosts[0].host=appointments-dev.local

# Deploy to staging namespace
helm install appointments-staging ./helm-chart `
  -f helm-chart/values-dev.yaml `
  -n embassy-staging --create-namespace `
  --set ingress.hosts[0].host=appointments-staging.local `
  --set config.environment=staging

# Update hosts file
# 127.0.0.1 appointments-dev.local
# 127.0.0.1 appointments-staging.local
```

---

## Performance Testing

### Generate Load
```powershell
# Using Apache Bench (install separately)
ab -n 1000 -c 10 http://appointments.local/

# Watch scaling
kubectl get hpa -n embassy-appointments -w
```

---

## Next Steps

1. ✅ Local deployment working
2. **Production Deployment**:
   - Review [Azure Architecture](05-AZURE-ARCHITECTURE.md)
   - Review [GCP Architecture](06-GCP-ARCHITECTURE.md)
3. **CI/CD Setup**: Configure GitHub Actions or Azure DevOps
4. **Monitoring**: Set up Prometheus and Grafana
5. **Security**: Implement secrets management, network policies

---

## Support

### Get Help
- **View logs**: `kubectl logs <pod-name> -n embassy-appointments`
- **Check events**: `kubectl get events -n embassy-appointments`
- **Describe resources**: `kubectl describe <resource-type> <name> -n embassy-appointments`

### Common Resources
- [KIND Documentation](https://kind.sigs.k8s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)

---

**Congratulations!** You now have a fully functional Kubernetes deployment of the Embassy Appointment System running locally on your machine. 🎉
