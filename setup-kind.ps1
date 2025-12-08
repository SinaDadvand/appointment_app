# KIND cluster setup script for Embassy Appointment System (Windows PowerShell)
# Minimum commands required to run the app on KIND local machine

Write-Host "🚀 Setting up KIND cluster for Embassy Appointment System" -ForegroundColor Green

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Docker is not installed. Please install Docker Desktop first." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "❌ KIND is not installed. Please install KIND first." -ForegroundColor Red
    exit 1
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

# Install NGINX Ingress Controller
Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for deployment to be created
Start-Sleep -Seconds 5

# Patch ingress controller to run on control-plane node (which has port mappings)
Write-Host "Configuring ingress controller for KIND..." -ForegroundColor Yellow
kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"ingress-ready":"true"}}]'

# Wait for ingress controller to be ready
Write-Host "Waiting for ingress controller..." -ForegroundColor Yellow
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

Write-Host "✓ Ingress controller ready" -ForegroundColor Green

# Build Docker image
Write-Host "Building application Docker image..." -ForegroundColor Yellow
docker build -t embassy-appointments:latest .

# Load image into KIND cluster
Write-Host "Loading image into KIND cluster..." -ForegroundColor Yellow
kind load docker-image embassy-appointments:latest --name embassy-appointments

Write-Host "✓ Image loaded" -ForegroundColor Green

# Update hosts file (requires admin)
Write-Host "Updating hosts file..." -ForegroundColor Yellow
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsPath -Raw
if ($hostsContent -notmatch "appointments.local") {
    try {
        Add-Content -Path $hostsPath -Value "`n127.0.0.1 appointments.local" -Force
        Write-Host "✓ Hosts file updated" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Could not update hosts file. Please run PowerShell as Administrator or manually add:" -ForegroundColor Yellow
        Write-Host "  127.0.0.1 appointments.local" -ForegroundColor Cyan
        Write-Host "  to C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Cyan
    }
}
else {
    Write-Host "✓ Hosts file already configured" -ForegroundColor Green
}

Write-Host "`n✅ Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Deploy the application:"
helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments --create-namespace 

Write-Host ""
Write-Host "2. Wait for pods to be ready (30-60 seconds):"
kubectl get pods -n embassy-appointments -w

Write-Host ""
Write-Host "3. Access the application:"
Write-Host "   http://appointments.local" -ForegroundColor White
Write-Host ""
Write-Host "Alternative access method:"
Write-Host "   kubectl port-forward svc/appointments-embassy-appointments 8080:80 -n embassy-appointments" -ForegroundColor White
Write-Host "   Then open: http://localhost:8080" -ForegroundColor White
Write-Host ""
