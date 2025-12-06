# KIND Cluster Setup - Step-by-Step Walkthrough

This guide walks you through the **manual setup** of a KIND (Kubernetes in Docker) cluster for the Embassy Appointment System. Follow each step carefully and verify the expected outcomes.

---

## 📋 Prerequisites

Before you begin, ensure you have the following installed:
- **Docker Desktop** (running)
- **kubectl** (Kubernetes CLI)
- **Helm 3** (Package manager)
- **KIND** (Kubernetes in Docker)
- **Git** (to clone the repository)

### Installing Prerequisites

If you don't have these tools installed, follow these steps:

#### 1. Install Docker Desktop

**Windows**:
```powershell
# Download and install from official website
Start-Process "https://www.docker.com/products/docker-desktop"

# Or using winget
winget install Docker.DockerDesktop

# Or using Chocolatey
choco install docker-desktop
```

After installation:
- Start Docker Desktop
- Wait for it to fully initialize (check system tray icon)
- Verify: `docker --version`

#### 2. Install kubectl

**Windows**:
```powershell
# Using winget
winget install Kubernetes.kubectl

# Or using Chocolatey
choco install kubernetes-cli

# Or manual download
curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
# Move to a directory in your PATH, e.g., C:\Windows\System32\
Move-Item .\kubectl.exe C:\Windows\System32\kubectl.exe -Force
```

Verify: `kubectl version --client`

#### 3. Install Helm

**Windows**:
```powershell
# Using winget
winget install Helm.Helm

# Or using Chocolatey
choco install kubernetes-helm

# Or using PowerShell script
Invoke-WebRequest -Uri https://get.helm.sh/helm-v3.13.0-windows-amd64.zip -OutFile helm.zip
Expand-Archive -Path helm.zip -DestinationPath .
Move-Item .\windows-amd64\helm.exe C:\Windows\System32\helm.exe -Force
Remove-Item helm.zip, windows-amd64 -Recurse -Force
```

Verify: `helm version`

#### 4. Install KIND

**Windows**:
```powershell
# Using winget
winget install Kubernetes.kind

# Or using Chocolatey
choco install kind

# Or manual download
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe C:\Windows\System32\kind.exe -Force
```

Verify: `kind --version`

#### 5. Install Git (if needed)

**Windows**:
```powershell
# Using winget
winget install Git.Git

# Or using Chocolatey
choco install git

# Or download from
Start-Process "https://git-scm.com/download/win"
```

Verify: `git --version`

---

## 🎯 Overview

You will:
1. Verify prerequisites
2. Create a KIND cluster with 3 nodes
3. Install NGINX Ingress Controller
4. Install Metrics Server for auto-scaling
5. Build and load the Docker image
6. Configure local DNS
7. Deploy the application with Helm (namespace created automatically)
8. Test the application

**Estimated Time**: 15-20 minutes

**Note**: You don't need to manually create the namespace - Helm will create it automatically during deployment.

---

## Step 1: Verify Prerequisites

**Who**: You (Developer/Operator)

**What**: Confirm all required tools are installed and Docker is running.

**Commands**:
```powershell
# Check Docker
docker --version
docker ps

# Check kubectl
kubectl version --client

# Check Helm
helm version

# Check KIND
kind --version
```

**Expected Output**:
```
Docker version 24.x.x
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES

Client Version: v1.28.x

version.BuildInfo{Version:"v3.13.x", ...}

kind v0.20.0 go1.21.x windows/amd64
```

**Why**: Ensures you have all necessary tools before proceeding.

**Troubleshooting**:
- If Docker is not running: Start Docker Desktop and wait for it to fully initialize
- If any tool is missing: Install it using the appropriate package manager (winget, chocolatey, or manual download)

---

## Step 2: Navigate to Project Directory

**Who**: You (Developer)

**What**: Change to the appointment_app directory where all files are located.

**Commands**:
```powershell
cd "C:\Users\sinad\VS Code\appointment_app"
```

**Expected Output**:
```
# Current directory changes to appointment_app
```

**Why**: All subsequent commands assume you're in the project root directory.

---

## Step 3: Create KIND Cluster

**Who**: You (Operator)

**What**: Create a multi-node Kubernetes cluster running inside Docker containers using the provided configuration.

**Commands**:
```powershell
kind create cluster --config kind-config.yaml --wait 5m
```

**Expected Output**:
```
Creating cluster "embassy-appointments" ...
 ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-embassy-appointments"
You can now use your cluster with:

kubectl cluster-info --context kind-embassy-appointments
```

**Why**: Creates a 3-node cluster (1 control-plane, 2 workers) with port mappings for HTTP/HTTPS traffic.

**What Happens**:
- Downloads Kubernetes node image (~300MB if not cached)
- Creates 3 Docker containers acting as Kubernetes nodes
- Configures networking and storage
- Sets up kubectl context

**Verification**:
```powershell
kubectl get nodes
```

**Expected**:
```
NAME                                STATUS   ROLES           AGE   VERSION
embassy-appointments-control-plane  Ready    control-plane   2m    v1.27.3
embassy-appointments-worker         Ready    <none>          2m    v1.27.3
embassy-appointments-worker2        Ready    <none>          2m    v1.27.3
```

---

## Step 4: Wait for Cluster Ready

**Who**: You (Operator)

**What**: Ensure all nodes are fully ready before proceeding.

**Commands**:
```powershell
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

**Expected Output**:
```
node/embassy-appointments-control-plane condition met
node/embassy-appointments-worker condition met
node/embassy-appointments-worker2 condition met
```

**Why**: Prevents errors when installing components by ensuring cluster is stable.

---

## Step 5: Install NGINX Ingress Controller

**Who**: You (Operator)

**What**: Deploy an ingress controller to route external HTTP traffic to your application.

**Commands**:
```powershell
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait a few seconds for deployment to be created
Start-Sleep -Seconds 5

# Ensure the ingress controller runs on the control-plane node (which has port mappings)
kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"ingress-ready":"true"}}]'
```

**Expected Output**:
```
namespace/ingress-nginx created
serviceaccount/ingress-nginx created
configmap/ingress-nginx-controller created
clusterrole.rbac.authorization.k8s.io/ingress-nginx created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx created
role.rbac.authorization.k8s.io/ingress-nginx created
rolebinding.rbac.authorization.k8s.io/ingress-nginx created
service/ingress-nginx-controller-admission created
service/ingress-nginx-controller created
deployment.apps/ingress-nginx-controller created
job.batch/ingress-nginx-admission-create created
job.batch/ingress-nginx-admission-patch created
deployment.apps/ingress-nginx-controller patched
```

**Why**: The NGINX Ingress Controller is essential for exposing your application to external traffic. Here's why you need it:

1. **External Access**: Without an Ingress Controller, your Kubernetes services are only accessible inside the cluster. The Ingress Controller acts as a gateway, allowing external HTTP/HTTPS traffic to reach your application.

2. **Domain-Based Routing**: It enables you to use friendly domain names (like `appointments.local`) instead of IP addresses and ports. The controller reads Ingress resources and configures routing rules automatically.

3. **Layer 7 Load Balancing**: Unlike basic Layer 4 load balancing (TCP/UDP), the Ingress Controller operates at Layer 7 (HTTP/HTTPS), allowing it to:
   - Route based on hostnames and URL paths
   - Handle SSL/TLS termination
   - Implement URL rewriting and redirects
   - Add custom headers

4. **Single Entry Point**: Instead of exposing each service with its own LoadBalancer (which can be expensive in cloud environments), one Ingress Controller handles all incoming traffic and routes it to the appropriate services.

5. **KIND-Specific Configuration**: The KIND-specific manifest configures the Ingress Controller to work with KIND's port mappings (80→30080, 443→30443), allowing traffic from your host machine to reach the cluster.

**What It Does**:
- **Acts as Reverse Proxy**: Receives all external HTTP/HTTPS requests and forwards them to the correct Kubernetes services based on routing rules defined in Ingress resources
- **SSL/TLS Termination**: Handles HTTPS encryption/decryption so your application pods can communicate using plain HTTP internally
- **Health Monitoring**: Continuously monitors backend services and removes unhealthy pods from rotation
- **Request Routing**: Routes `http://appointments.local/` to the appointments service, `http://appointments.local/appointments` to the list endpoint, etc.

**Architecture**:
```
External Traffic (Your Browser)
         ↓
http://appointments.local
         ↓
localhost:80 (Your Machine)
         ↓
KIND Node Port 30080
         ↓
NGINX Ingress Controller Pod
         ↓
Reads Ingress Resource Rules
         ↓
Routes to appointments-embassy-appointments Service (ClusterIP)
         ↓
Service Load Balances to Application Pod(s)
         ↓
Your Application (Flask/Gunicorn)
```

**What Happens During Installation**:
- Creates `ingress-nginx` namespace to isolate ingress components
- Deploys NGINX Ingress Controller deployment (the actual reverse proxy)
- **Patches deployment to add `nodeSelector`** ensuring the pod runs on the control-plane node (which has the host port mappings 80→80, 443→443)
- Creates services:
  - `ingress-nginx-controller`: NodePort service that exposes ports 80/443
  - `ingress-nginx-controller-admission`: Validates Ingress resources
- Configures RBAC (Role-Based Access Control) so the controller can read Ingress resources, Services, and Endpoints
- Sets up admission webhooks for validating Ingress configurations
- Uses `hostPort` configuration to bind directly to ports 80 and 443 on the control-plane node

**Why the NodeSelector Patch is Critical**:
- KIND's control-plane node has port mappings configured: `0.0.0.0:80->80/tcp` and `0.0.0.0:443->443/tcp`
- The ingress controller uses `hostPort: 80` and `hostPort: 443` in its pod spec
- Without the `nodeSelector`, the pod might be scheduled on a worker node that doesn't have these port mappings
- The `ingress-ready=true` label is automatically set on the control-plane node by KIND
- This ensures the ingress controller pod always runs where the ports are mapped correctly

**Without Ingress Controller**:
You would need to:
- Use `kubectl port-forward` for each service (manual, stops when terminal closes)
- Expose services as LoadBalancer type (doesn't work well in KIND)
- Access via `http://localhost:<random-port>` (not user-friendly)
- Manually manage routing and load balancing

---

## Step 6: Wait for Ingress Controller

**Who**: You (Operator)

**What**: Wait for the ingress controller to be fully operational.

**Commands**:
```powershell
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s
```

**Expected Output**:
```
pod/ingress-nginx-controller-xxxxx condition met
```

**Why**: Ensures ingress is ready to route traffic before deploying the application.

**Verification**:
```powershell
kubectl get pods -n ingress-nginx
```

**Expected**:
```
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

**Verification - Ensure it's on the control-plane node**:
```powershell
kubectl get pods -n ingress-nginx -o wide
```

**Expected**:
```
NAME                                        READY   STATUS    RESTARTS   AGE   NODE
ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m    embassy-appointments-control-plane
```

**Important**: The NODE column should show `embassy-appointments-control-plane`. If it shows a worker node, the nodeSelector patch didn't apply correctly, and the application won't be accessible.

---

## Step 7: Install Metrics Server

**Who**: You (Operator)

**What**: Deploy the Metrics Server to enable CPU/memory metrics collection for monitoring and auto-scaling.

**Commands**:
```powershell
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait a few seconds for deployment to be created
Start-Sleep -Seconds 5

# Patch for KIND (disable TLS verification)
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**Expected Output**:
```
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
deployment.apps/metrics-server patched
```

**Why You Need Metrics Server**:

Metrics Server is a crucial component for Kubernetes cluster observability and automation. Here's why it's essential:

1. **Auto-Scaling (HPA)**: The Horizontal Pod Autoscaler (HPA) requires real-time CPU and memory metrics to make intelligent scaling decisions. Without Metrics Server, HPA cannot function.

2. **Resource Monitoring**: Enables the `kubectl top` command to show real-time resource consumption:
   - `kubectl top nodes` - View CPU/memory usage across all nodes
   - `kubectl top pods` - View resource consumption per pod
   - Essential for capacity planning and troubleshooting

3. **Scheduling Decisions**: Kubernetes scheduler can make better pod placement decisions when it knows actual resource usage vs. just resource requests/limits.

4. **Performance Insights**: Provides visibility into whether your application is:
   - Under-provisioned (hitting resource limits)
   - Over-provisioned (wasting resources)
   - Running efficiently within allocated resources

5. **Cost Optimization**: In cloud environments, understanding actual resource usage helps optimize node sizes and reduce costs.

**What Metrics Server Does**:

- **Collects Metrics**: Queries kubelet on each node every 15 seconds (by default) to collect:
  - CPU usage (in millicores)
  - Memory usage (in bytes)
  - For both nodes and pods

- **Aggregates Data**: Stores a short-term (typically 1-2 minutes) rolling window of metrics in memory

- **Exposes API**: Provides metrics via the Kubernetes Metrics API (`metrics.k8s.io/v1beta1`)
  - Other tools (HPA, kubectl top, dashboard) consume this API

- **Lightweight**: Uses minimal resources (~10-20 MB RAM) and doesn't persist historical data (unlike Prometheus)

**Architecture**:
```
Kubelet (on each node)
    ↓
Exposes metrics at /stats/summary
    ↓
Metrics Server (polls every 15s)
    ↓
Aggregates & stores in-memory
    ↓
Exposes Metrics API
    ↓
Consumed by:
- HPA (for scaling decisions)
- kubectl top (for CLI visibility)
- Kubernetes Dashboard
- VPA (Vertical Pod Autoscaler)
```

**What We're Patching and Why**:

The patch command adds the `--kubelet-insecure-tls` flag to the Metrics Server deployment. Here's what this does:

**The Patch**:
```json
[{
  "op": "add",
  "path": "/spec/template/spec/containers/0/args/-",
  "value": "--kubelet-insecure-tls"
}]
```

**What It Does**:
- **op: "add"**: Adds a new item to an array
- **path**: Targets the container arguments in the deployment spec
- **value**: Adds the `--kubelet-insecure-tls` flag

**Why This Is Needed for KIND**:

1. **TLS Certificate Problem**: In production Kubernetes, kubelets have proper TLS certificates signed by the cluster CA. Metrics Server validates these certificates for security.

2. **KIND's Self-Signed Certificates**: KIND uses self-signed certificates that don't match the kubelet's hostname/IP. By default, Metrics Server will reject these certificates.

3. **The Solution**: `--kubelet-insecure-tls` tells Metrics Server to:
   - Skip TLS certificate verification when connecting to kubelets
   - Still use HTTPS encryption, but don't validate the certificate
   - Only appropriate for development/testing environments like KIND

4. **Security Trade-off**: 
   - ✅ **OK for local development**: KIND is on localhost, no external network exposure
   - ❌ **NOT for production**: Always use proper certificates in production clusters

**Alternative Flags** (for reference, not needed for this tutorial):
- `--kubelet-preferred-address-types`: Specifies how to reach kubelets (InternalIP, Hostname, etc.)
- `--kubelet-use-node-status-port`: Use the status port for kubelet connections
- `--metric-resolution`: How often to scrape metrics (default: 15s)

**What Happens During Installation**:
1. Creates `metrics-server` deployment in `kube-system` namespace
2. Sets up RBAC permissions to read node/pod metrics
3. Registers APIService for `metrics.k8s.io/v1beta1`
4. Metrics Server starts polling kubelets
5. After 15-30 seconds, metrics become available via API

**Benefits Summary**:
- ✅ **Enables Auto-Scaling**: Required for HPA to function
- ✅ **Real-Time Monitoring**: View live resource consumption
- ✅ **Troubleshooting**: Identify resource bottlenecks quickly
- ✅ **Capacity Planning**: Make informed decisions about resource allocation
- ✅ **Lightweight**: Minimal overhead compared to full monitoring stacks
- ✅ **Built-in Integration**: Native Kubernetes component, no extra configuration needed

**Verification** (wait 30-60 seconds for metrics to populate):
```powershell
kubectl top nodes
```

**Expected**:
```
NAME                                CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
embassy-appointments-control-plane  150m         7%     800Mi           10%
embassy-appointments-worker         100m         5%     600Mi           8%
embassy-appointments-worker2        100m         5%     600Mi           8%
```

**Troubleshooting Metrics Server**:

If `kubectl top nodes` shows an error:
```powershell
# Check if metrics-server pod is running
kubectl get pods -n kube-system | Select-String metrics-server

# Should show:
# metrics-server-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Check logs if not working
kubectl logs -n kube-system deployment/metrics-server

# Verify APIService is available
kubectl get apiservice v1beta1.metrics.k8s.io

# Should show:
# NAME                     SERVICE                      AVAILABLE   AGE
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True        2m
```

---

## Step 8: Build Application Docker Image

**Who**: You (Developer)

**What**: Build the application container image from the Dockerfile.

**Commands**:
```powershell
docker build -t embassy-appointments:latest .
```

**Expected Output**:
```
[+] Building 45.2s (14/14) FINISHED
 => [internal] load build definition from Dockerfile
 => [internal] load .dockerignore
 => [builder 1/4] FROM docker.io/library/python:3.11-slim
 => [builder 2/4] COPY requirements.txt .
 => [builder 3/4] RUN pip install --user --no-cache-dir -r requirements.txt
 => [runtime 1/5] WORKDIR /app
 => [runtime 2/5] COPY --from=builder /root/.local /root/.local
 => [runtime 3/5] COPY app.py .
 => [runtime 4/5] COPY templates/ templates/
 => exporting to image
 => => naming to docker.io/library/embassy-appointments:latest
```

**Why**: Creates a containerized version of the application ready for deployment.

**What Happens**:
- Multi-stage build executes
- Dependencies installed in builder stage
- Application files copied to runtime stage
- Final image ~150MB

**Verification**:
```powershell
docker images embassy-appointments
```

**Expected**:
```
REPOSITORY              TAG       IMAGE ID       CREATED          SIZE
embassy-appointments    latest    abc123def456   10 seconds ago   150MB
```

---

## Step 9: Load Image into KIND Cluster

**Who**: You (Operator)

**What**: Transfer the Docker image into the KIND cluster's internal registry.

**Commands**:
```powershell
kind load docker-image embassy-appointments:latest --name embassy-appointments
```

**Expected Output**:
```
Image: "embassy-appointments:latest" with ID "sha256:abc123..." not yet present on node "embassy-appointments-control-plane", loading...
Image: "embassy-appointments:latest" with ID "sha256:abc123..." not yet present on node "embassy-appointments-worker", loading...
Image: "embassy-appointments:latest" with ID "sha256:abc123..." not yet present on node "embassy-appointments-worker2", loading...
```

**Why**: KIND nodes can't access your local Docker images directly; they need to be loaded into each node.

**What Happens**:
- Image is copied from local Docker to each KIND node
- Kubernetes can now pull the image when creating pods

---

## Step 10: Configure Local DNS (Hosts File)

**Who**: You (Administrator)

**What**: Add a DNS entry to map appointments.local to localhost.

**Commands** (requires Administrator PowerShell):
```powershell
# Option 1: Automated (run PowerShell as Administrator)
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n127.0.0.1 appointments.local" -Force

# Option 2: Manual
# Open Notepad as Administrator
# File > Open > C:\Windows\System32\drivers\etc\hosts
# Add this line at the end:
# 127.0.0.1 appointments.local
# Save and close
```

**Expected Outcome**:
- No error messages
- File C:\Windows\System32\drivers\etc\hosts updated

**Why**: Allows you to access the application via http://appointments.local instead of http://localhost.

**Verification**:
```powershell
ping appointments.local
```

**Expected**:
```
Pinging appointments.local [127.0.0.1] with 32 bytes of data:
Reply from 127.0.0.1: bytes=32 time<1ms TTL=128
```

---

## Step 11: Deploy Application with Helm

**Who**: You (Operator)

**What**: Deploy the Embassy Appointment application using Helm with development values. Helm will automatically create the namespace.

**Commands**:
```powershell
helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments --create-namespace
```

**Expected Output**:
```
NAME: appointments
LAST DEPLOYED: Fri Dec  5 10:30:00 2025
NAMESPACE: embassy-appointments
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

**Why**: Helm packages all Kubernetes resources and deploys them with consistent configuration. The `--create-namespace` flag tells Helm to create the namespace if it doesn't exist.

**What Happens**:
- Namespace `embassy-appointments` created automatically by Helm
- ConfigMap created with application settings
- Secret created with sensitive data
- Deployment created (1 replica in dev)
- Service created (ClusterIP)
- Ingress created (HTTP routing)
- PersistentVolumeClaim created for data storage

**Verification**:
```powershell
# Check Helm release
helm list -n embassy-appointments

# Check namespace was created
kubectl get namespace embassy-appointments
```

**Expected**:
```
NAME            NAMESPACE               REVISION  UPDATED                    STATUS    CHART                           APP VERSION
appointments    embassy-appointments    1         2025-12-05 10:30:00 PST    deployed  embassy-appointments-1.0.0      1.0.0

NAME                   STATUS   AGE
embassy-appointments   Active   10s
```

**Important Note**: 
- We use `--create-namespace` to let Helm manage the namespace lifecycle
- This ensures proper Helm ownership and makes cleanup easier
- Don't manually create the namespace before running Helm install

---

## Step 12: Wait for Pods to be Ready

**Who**: You (Operator)

**What**: Monitor pod creation and wait for them to reach Running status.

**Commands**:
```powershell
# Watch pods (Ctrl+C to stop)
kubectl get pods -n embassy-appointments -w

# Or wait for ready condition
kubectl wait --for=condition=Ready pods --all -n embassy-appointments --timeout=300s
```

**Expected Output**:
```
NAME                                              READY   STATUS    RESTARTS   AGE
appointments-embassy-appointments-xxxxxxxxx-xxxxx 0/1     Pending   0          5s
appointments-embassy-appointments-xxxxxxxxx-xxxxx 0/1     ContainerCreating   0          10s
appointments-embassy-appointments-xxxxxxxxx-xxxxx 1/1     Running   0          30s
pod/appointments-embassy-appointments-xxxxxxxxx-xxxxx condition met
```

**Why**: Ensures the application is fully deployed before attempting to access it.

**Timeline**:
- 0-10s: Pending (scheduler assigns node)
- 10-25s: ContainerCreating (image pull, container start)
- 25-30s: Running (health checks passing)

---

## Step 13: Access the Application

---

## Step 14: Access the Application

**Who**: You (End User)

**What**: Open the application in your web browser.

**Commands**:
```powershell
# Open in default browser
Start-Process "http://appointments.local"

# Or manually navigate to:
# http://appointments.local
```

**Expected Outcome**:
- Browser opens to the Embassy Appointment System homepage
- You see a Bootstrap-styled page with:
  - Navigation bar with "Embassy Appointment System" branding
  - Hero section with embassy name
  - Appointment booking form with fields:
    - Full Name
    - Email Address
    - Passport Number
    - Phone Number
    - Medical Exam Date
    - Preferred Appointment Date
    - Preferred Appointment Time
  - Submit button

**Why**: Verifies end-to-end deployment success from cluster to browser.

**Screenshot Expectation**:
```
┌─────────────────────────────────────────────┐
│ Embassy Appointment System    [Home] [List] │
├─────────────────────────────────────────────┤
│                                              │
│   Welcome to U.S. Embassy                   │
│   Visa Appointment System                   │
│                                              │
│   Schedule Your Appointment                 │
  │   ┌───────────────────────────────┐        │
│   │ Full Name:                    │        │
│   │ ...                           │        │
│   │ [    Schedule Appointment   ] │        │
│   └───────────────────────────────┘        │
└─────────────────────────────────────────────┘
```

---

## Step 14: Test Appointment Booking

**Who**: You (Tester/End User)

**What**: Submit a test appointment to verify full functionality.

**Actions**:
1. Fill in the form:
   - **Full Name**: John Doe
   - **Email**: john.doe@example.com
   - **Passport Number**: AB1234567
   - **Phone Number**: +1-555-123-4567
   - **Medical Exam Date**: Yesterday's date (within 180 days)
   - **Preferred Appointment Date**: Tomorrow's date
   - **Preferred Appointment Time**: 10:00 AM
2. Click "Schedule Appointment"

**Expected Outcome**:
- Page redirects to appointment confirmation page
- You see:
  - ✅ Success message: "Appointment Scheduled Successfully!"
  - Confirmation ID (e.g., APPT-1702)
  - **Applicant Information**:
    - Name: John Doe
    - Email: john.doe@example.com
    - Passport: AB1234567
    - Phone: +1-555-123-4567
  - **Appointment Schedule**:
    - Date: Tomorrow's date
    - Time: 10:00 AM
    - Status: ✓ Valid
  - Important information panel with next steps
  - "Print Confirmation" button

**Why**: Validates the entire application workflow from form submission to database storage to confirmation display.

---

## Step 15: View All Appointments

**Who**: You (Administrator)

**What**: Navigate to the appointments list page.

**Actions**:
1. Click "View Appointments" in the navigation bar
2. Or navigate to: http://appointments.local/appointments

**Expected Outcome**:
- Table displaying all appointments:

```
| Name     | Passport  | Email                | Appointment       | Status  | Actions |
|----------|-----------|----------------------|-------------------|---------|---------|  
| John Doe | AB1234567 | john.doe@example.com | Tomorrow 10:00 AM | ✓ Valid | View    |
```

- Click "View" to see appointment details again

**Why**: Tests the appointment list view and database query functionality.

---

## Step 16: Test Health Endpoints

**Who**: You (DevOps/SRE)

**What**: Verify health check endpoints respond correctly.

**Commands**:
```powershell
# Health check (liveness probe)
curl http://appointments.local/health

# Readiness check
curl http://appointments.local/ready

# Metrics endpoint
curl http://appointments.local/metrics
```

**Expected Output**:

**Health**:
```json
{
  "status": "healthy",
  "timestamp": "2025-12-05T18:30:00Z",
  "version": "1.0.0",
  "database": "connected"
}
```

**Ready**:
```json
{
  "status": "ready",
  "checks": {
    "database": "ok",
    "startup": "complete"
  }
}
```

**Metrics**:
```
# HELP appointments_total Total number of appointments
# TYPE appointments_total gauge
appointments_total 1.0
# HELP appointments_pending Pending appointments
# TYPE appointments_pending gauge
appointments_pending 0.0
# HELP app_version Application version
# TYPE app_version gauge
app_version{version="1.0.0"} 1.0
```

**Why**: Confirms Kubernetes health probes and monitoring integrations work correctly.

---

## Step 17: Monitor Application Logs

**Who**: You (Developer/SRE)

**What**: View application logs to see what's happening inside the container.

**Commands**:
```powershell
# Get pod name
kubectl get pods -n embassy-appointments

# View logs (replace pod name)
kubectl logs -f appointments-embassy-appointments-xxxxxxxxx-xxxxx -n embassy-appointments
```

**Expected Output**:
```
[2025-12-05 18:30:00 +0000] [1] [INFO] Starting gunicorn 21.2.0
[2025-12-05 18:30:00 +0000] [1] [INFO] Listening at: http://0.0.0.0:8080 (1)
[2025-12-05 18:30:00 +0000] [1] [INFO] Using worker: sync
[2025-12-05 18:30:00 +0000] [8] [INFO] Booting worker with pid: 8
[2025-12-05 18:30:00 +0000] [11] [INFO] Booting worker with pid: 11
INFO:werkzeug:192.168.1.1 - - [05/Dec/2025 18:32:15] "GET / HTTP/1.1" 200 -
INFO:werkzeug:192.168.1.1 - - [05/Dec/2025 18:32:45] "POST /appointments HTTP/1.1" 302 -
```

**Why**: Helps troubleshoot issues and understand application behavior.

---

## Step 18: Verify Resource Usage

**Who**: You (SRE)

**What**: Check CPU and memory consumption to ensure resources are within limits.

**Commands**:
```powershell
kubectl top pods -n embassy-appointments
```

**Expected Output**:
```
NAME                                              CPU(cores)   MEMORY(bytes)
appointments-embassy-appointments-xxxxxxxxx-xxxxx 5m           85Mi
```

**Why**: Monitors resource consumption to ensure pods operate within allocated resource limits (100m CPU, 128Mi RAM in dev).

**What to Look For**:
- CPU < 100m (under limit)
- Memory < 128Mi (under limit)
- No OOMKilled or CrashLoopBackOff status

---

## Step 19: Test Auto-Scaling (Optional)

**Who**: You (SRE)

**What**: Generate load to trigger horizontal pod autoscaling.

**Commands**:
```powershell
# Check current HPA status
kubectl get hpa -n embassy-appointments

# Expected: minReplicas: 1, maxReplicas: 3, currentReplicas: 1

# Generate load (run in separate terminal, requires Apache Bench or similar)
# ab -n 10000 -c 50 http://appointments.local/

# Watch HPA scale up
kubectl get hpa -n embassy-appointments -w
```

**Expected Outcome**:
- HPA detects high CPU usage
- Scales up to 2-3 replicas
- Load distributes across pods
- After load stops, scales back down to 1 replica (after 5 minutes)

**Why**: Validates auto-scaling configuration works correctly.

---

## ✅ Success Criteria

You have successfully set up the KIND cluster if:

- ✅ KIND cluster running with 3 nodes
- ✅ NGINX Ingress Controller operational
- ✅ Metrics Server providing node/pod metrics
- ✅ Application pod(s) in Running state
- ✅ http://appointments.local accessible in browser
- ✅ Can create appointments successfully
- ✅ Can view appointments list
- ✅ Health endpoints return healthy status
- ✅ Logs show Gunicorn workers running
- ✅ Resource usage within limits

---

## 🧹 Cleanup (When Done)

**Who**: You (Operator)

**What**: Remove all resources when you're finished testing.

**Commands**:
```powershell
# Uninstall Helm release
helm uninstall appointments -n embassy-appointments

# Delete namespace
kubectl delete namespace embassy-appointments

# Delete KIND cluster
kind delete cluster --name embassy-appointments

# Remove hosts entry (as Administrator)
# Edit C:\Windows\System32\drivers\etc\hosts
# Remove line: 127.0.0.1 appointments.local
```

**Expected Outcome**:
- All resources cleaned up
- Docker containers for KIND nodes removed
- No residual configuration

---

## 🐛 Troubleshooting

### Issue: Pods stuck in ContainerCreating

**Possible Causes**:
- Image not loaded into KIND
- Storage issues

**Solution**:
```powershell
# Check pod events
kubectl describe pod <pod-name> -n embassy-appointments

# Reload image
kind load docker-image embassy-appointments:latest --name embassy-appointments

# Delete pod to recreate
kubectl delete pod <pod-name> -n embassy-appointments
```

---

### Issue: Cannot access http://appointments.local

**Possible Causes**:
- Hosts file not updated
- Ingress controller not ready
- Pods not running

**Solution**:
```powershell
# Verify hosts file
ping appointments.local  # Should resolve to 127.0.0.1

# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl get ingress -n embassy-appointments

# Check application pods
kubectl get pods -n embassy-appointments
```

---

### Issue: Metrics Server not working

**Possible Causes**:
- TLS verification not disabled
- Pods not fully started

**Solution**:
```powershell
# Re-patch metrics server
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait 60 seconds and retry
kubectl top nodes
```

---

### Issue: Application shows database errors

**Possible Causes**:
- Database initialization failed
- Permissions issues

**Solution**:
```powershell
# Check logs for errors
kubectl logs <pod-name> -n embassy-appointments

# Restart pod
kubectl delete pod <pod-name> -n embassy-appointments
```

---

## 📚 What You Learned

By completing this walkthrough, you:

1. **Cluster Management**: Created and configured a multi-node Kubernetes cluster
2. **Ingress Configuration**: Set up external access via NGINX Ingress
3. **Monitoring**: Installed Metrics Server for resource monitoring
4. **Container Registry**: Learned KIND image loading process
5. **DNS Configuration**: Configured local DNS resolution
6. **Helm Deployment**: Deployed applications using Helm charts
7. **Health Checks**: Understood liveness, readiness, and startup probes
8. **Observability**: Viewed logs and metrics
9. **Auto-Scaling**: Tested horizontal pod autoscaling
10. **Troubleshooting**: Diagnosed and resolved common issues

---

## 🎯 Next Steps

Now that your local environment is working:

1. **Customize Configuration**: Modify `helm-chart/values-dev.yaml` to change settings
2. **Explore Helm Chart**: Review templates in `helm-chart/templates/`
3. **Test Production Values**: Deploy with `values-prod.yaml` to test production configuration
4. **Set up CI/CD**: Create GitHub Actions workflow for automated deployments
5. **Deploy to Cloud**: Follow [Azure](05-AZURE-ARCHITECTURE.md) or [GCP](06-GCP-ARCHITECTURE.md) guides

---

## 📞 Reference Commands

**Quick Reference**:
```powershell
# View all resources
kubectl get all -n embassy-appointments

# Describe deployment
kubectl describe deployment appointments-embassy-appointments -n embassy-appointments

# View configmap
kubectl get configmap -n embassy-appointments -o yaml

# View secret (encoded)
kubectl get secret -n embassy-appointments -o yaml

# Port-forward (alternative access)
kubectl port-forward -n embassy-appointments service/appointments-embassy-appointments 8080:80
# Then access: http://localhost:8080

# Helm upgrade after changes
helm upgrade appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments

# View Helm values
helm get values appointments -n embassy-appointments
```

---

**🎉 Congratulations!** You've successfully deployed a production-grade Kubernetes application locally using KIND!
