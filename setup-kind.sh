#!/bin/bash
# KIND cluster setup script for Embassy Appointment System

set -e

echo "🚀 Setting up KIND cluster for Embassy Appointment System"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo "❌ KIND is not installed. Installing KIND..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites satisfied${NC}"

# Create KIND cluster
echo -e "${YELLOW}Creating KIND cluster...${NC}"
kind create cluster --config kind-config.yaml --wait 5m

echo -e "${GREEN}✓ KIND cluster created${NC}"

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Create namespace
echo -e "${YELLOW}Creating namespace...${NC}"
kubectl create namespace embassy-appointments || true

# Install NGINX Ingress Controller
echo -e "${YELLOW}Installing NGINX Ingress Controller...${NC}"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller to be ready
echo -e "${YELLOW}Waiting for ingress controller...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Install Metrics Server (for HPA)
echo -e "${YELLOW}Installing Metrics Server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics server for KIND (insecure TLS)
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Build Docker image
echo -e "${YELLOW}Building application Docker image...${NC}"
docker build -t embassy-appointments:latest .

# Load image into KIND cluster
echo -e "${YELLOW}Loading image into KIND cluster...${NC}"
kind load docker-image embassy-appointments:latest --name embassy-appointments

# Update /etc/hosts (requires sudo)
echo -e "${YELLOW}Updating /etc/hosts (requires sudo)...${NC}"
if ! grep -q "appointments.local" /etc/hosts; then
    echo "127.0.0.1 appointments.local" | sudo tee -a /etc/hosts
fi

echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Deploy the application: helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments"
echo "2. Access the application: http://appointments.local"
echo "3. View pods: kubectl get pods -n embassy-appointments"
echo "4. View logs: kubectl logs -f deployment/appointments-embassy-appointments -n embassy-appointments"
