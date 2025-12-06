# KIND cluster setup script for Embassy Appointment System (Windows PowerShell)

Write-Host "🚀 Setting up KIND cluster for Embassy Appointment System" -ForegroundColor Green

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Docker is not installed. Please install Docker Desktop first." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "❌ KIND is not installed. Installing KIND..." -ForegroundColor Yellow
    curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
    Move-Item .\kind-windows-amd64.exe C:\Windows\System32\kind.exe -Force
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "❌ kubectl is not installed. Please install kubectl first." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Helm is not installed. Please install Helm first." -ForegroundColor Red
    exit 1
}

Write-Host "✓ All prerequisites satisfied" -ForegroundColor Green

# Create KIND cluster
Write-Host "Creating KIND cluster..." -ForegroundColor Yellow
kind create cluster --config kind-config.yaml --wait 5m

Write-Host "✓ KIND cluster created" -ForegroundColor Green

# Wait for cluster to be ready
Write-Host "Waiting for cluster to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Create namespace
Write-Host "Creating namespace..." -ForegroundColor Yellow
kubectl create namespace embassy-appointments 2>$null

# Install NGINX Ingress Controller
Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller to be ready
Write-Host "Waiting for ingress controller..." -ForegroundColor Yellow
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

# Install Metrics Server (for HPA)
Write-Host "Installing Metrics Server..." -ForegroundColor Yellow
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics server for KIND (insecure TLS)
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Build Docker image
Write-Host "Building application Docker image..." -ForegroundColor Yellow
docker build -t embassy-appointments:latest .

# Load image into KIND cluster
Write-Host "Loading image into KIND cluster..." -ForegroundColor Yellow
kind load docker-image embassy-appointments:latest --name embassy-appointments

# Update hosts file (requires admin)
Write-Host "Updating hosts file..." -ForegroundColor Yellow
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsPath -Raw
if ($hostsContent -notmatch "appointments.local") {
    Write-Host "Adding appointments.local to hosts file (requires admin privileges)..." -ForegroundColor Yellow
    Add-Content -Path $hostsPath -Value "`n127.0.0.1 appointments.local" -Force
}

Write-Host "`n✓ Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Deploy the application:"
Write-Host "   helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments"
Write-Host ""
Write-Host "2. Access the application: http://appointments.local"
Write-Host ""
Write-Host "3. View pods:"
Write-Host "   kubectl get pods -n embassy-appointments"
Write-Host ""
Write-Host "4. View logs:"
Write-Host "   kubectl logs -f deployment/appointments-embassy-appointments -n embassy-appointments"
