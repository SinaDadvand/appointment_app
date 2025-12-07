# Operations Guide

This guide covers day-to-day operational tasks for the Embassy Appointments application, including user access, application updates, and configuration management.

---

## Table of Contents

1. [User Access Methods](#user-access-methods)
2. [Application Updates](#application-updates)
3. [Configuration Management](#configuration-management)
4. [Monitoring and Logging](#monitoring-and-logging)
5. [Backup and Recovery](#backup-and-recovery)
6. [Troubleshooting](#troubleshooting)

---

## User Access Methods

### Local Development (KIND Cluster)

**End User Access**:
```
URL: http://appointments.local
```

**Setup Requirements**:
1. Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
   ```
   127.0.0.1 appointments.local
   ```
2. Ensure KIND cluster is running with port mappings
3. NGINX ingress controller must be on control-plane node

**Developer Access**:
```bash
# Direct pod access via port-forward
kubectl port-forward -n embassy-appointments \
  svc/appointments-embassy-appointments 8080:80

# Access via localhost:8080
curl http://localhost:8080

# View logs
kubectl logs -n embassy-appointments -l app.kubernetes.io/name=embassy-appointments --tail=50 -f

# Execute commands in pod
kubectl exec -it <pod-name> -n embassy-appointments -- /bin/sh
```

---

### Azure Production (AKS)

**End User Access**:
```
URL: https://appointments.yourdomain.com
```

**Access Flow**:
```
User → DNS → Azure Front Door (CDN/WAF) → Application Gateway (SSL) 
  → AKS Ingress Controller → Kubernetes Service → Pods
```

**Administrator Access**:

**1. Azure Portal**:
- Navigate to Azure Portal → Kubernetes services → Select cluster
- View Workloads, Services, Storage, Configuration
- Use Cloud Shell for kubectl commands

**2. Azure CLI**:
```bash
# Login
az login

# Get cluster credentials
az aks get-credentials \
  --resource-group embassy-appointments-rg \
  --name embassy-appointments-aks

# View resources
kubectl get all -n embassy-appointments

# View logs
az aks browse --resource-group embassy-appointments-rg \
  --name embassy-appointments-aks
```

**3. Azure Monitor**:
- Container Insights for pod/node metrics
- Log Analytics for centralized logging
- Application Insights for request tracing

---

### GCP Production (GKE)

**End User Access**:
```
URL: https://appointments.yourdomain.com
```

**Access Flow**:
```
User → DNS → Cloud CDN → Cloud Armor (WAF) → Load Balancer (SSL) 
  → GKE Ingress Controller → Kubernetes Service → Pods
```

**Administrator Access**:

**1. Cloud Console**:
- Navigate to Google Cloud Console → Kubernetes Engine → Clusters
- View Workloads, Services & Ingress, Storage, Logs
- Use Cloud Shell for kubectl commands

**2. gcloud CLI**:
```bash
# Login
gcloud auth login

# Connect to cluster
gcloud container clusters get-credentials \
  embassy-appointments-gke \
  --region=us-central1

# View resources
kubectl get all -n embassy-appointments

# View logs in Cloud Logging
gcloud logging read \
  "resource.type=k8s_container AND resource.labels.namespace_name=embassy-appointments" \
  --limit=50
```

**3. Cloud Monitoring**:
- GKE dashboards for cluster/pod metrics
- Cloud Logging for centralized logs
- Cloud Trace for request tracing

---

## Application Updates

### Update Strategy Overview

The application uses **rolling updates** to ensure zero-downtime deployments:
- New pods are created before old pods are terminated
- Health checks ensure new pods are ready before traffic is routed
- Rollback capability in case of issues

---

### Local Development Updates

**Build and Deploy**:
```bash
# 1. Make code changes in app.py or templates/

# 2. Rebuild Docker image
docker build -t embassy-appointments:latest .

# 3. Load into KIND cluster
kind load docker-image embassy-appointments:latest --name embassy-appointments

# 4. Restart deployment to pick up new image
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments

# 5. Verify rollout
kubectl rollout status deployment appointments-embassy-appointments \
  -n embassy-appointments

# 6. Test
curl http://appointments.local
```

**Quick Updates with Helm**:
```bash
# Update Helm values or templates
helm upgrade appointments ./helm-chart \
  -f helm-chart/values-dev.yaml \
  -n embassy-appointments
```

---

### Azure Production Updates

**CI/CD Pipeline (Recommended)**:

1. **Push code to GitHub**:
   ```bash
   git add .
   git commit -m "feat: add new feature"
   git push origin main
   ```

2. **Azure DevOps Pipeline triggers** and executes the following stages:

   **Stage 1: Run Tests**
   ```yaml
   # azure-pipelines.yml
   - stage: Test
     jobs:
     - job: RunTests
       pool:
         vmImage: 'ubuntu-latest'
       steps:
       - task: UsePythonVersion@0
         inputs:
           versionSpec: '3.11'
       
       - script: |
           pip install -r requirements.txt
           pip install pytest pytest-cov
           pytest tests/ --cov=. --cov-report=xml
         displayName: 'Run unit tests'
       
       - task: PublishTestResults@2
         inputs:
           testResultsFiles: '**/test-*.xml'
           testRunTitle: 'Python Tests'
   ```

   **Stage 2: Build Docker Image**
   ```yaml
   - stage: Build
     dependsOn: Test
     condition: succeeded()
     jobs:
     - job: BuildImage
       pool:
         vmImage: 'ubuntu-latest'
       steps:
       - task: Docker@2
         displayName: 'Build Docker image'
         inputs:
           command: build
           repository: 'embassy-appointments/app'
           dockerfile: 'Dockerfile'
           tags: |
             $(Build.BuildId)
             latest
   ```

   **Stage 3: Push to Azure Container Registry**
   ```yaml
   - task: Docker@2
     displayName: 'Push to ACR'
     inputs:
       command: push
       containerRegistry: 'embassyappointmentsacr'  # Service connection name
       repository: 'embassy-appointments/app'
       tags: |
         $(Build.BuildId)
         latest
   ```

   **Stage 4: Deploy to AKS using Helm**
   ```yaml
   - stage: Deploy
     dependsOn: Build
     condition: succeeded()
     jobs:
     - deployment: DeployToAKS
       environment: 'production'
       pool:
         vmImage: 'ubuntu-latest'
       strategy:
         runOnce:
           deploy:
             steps:
             # Install Helm
             - task: HelmInstaller@1
               displayName: 'Install Helm'
               inputs:
                 helmVersionToInstall: '3.12.0'
             
             # Install kubectl
             - task: KubectlInstaller@0
               displayName: 'Install kubectl'
               inputs:
                 kubectlVersion: 'latest'
             
             # Get AKS credentials
             - task: AzureCLI@2
               displayName: 'Get AKS credentials'
               inputs:
                 azureSubscription: 'Azure-Subscription-Connection'
                 scriptType: 'bash'
                 scriptLocation: 'inlineScript'
                 inlineScript: |
                   az aks get-credentials \
                     --resource-group embassy-appointments-rg \
                     --name embassy-appointments-aks \
                     --overwrite-existing
             
             # Deploy with Helm
             - task: HelmDeploy@0
               displayName: 'Helm upgrade'
               inputs:
                 connectionType: 'Kubernetes Service Connection'
                 kubernetesServiceConnection: 'AKS-Connection'
                 namespace: 'embassy-appointments'
                 command: 'upgrade'
                 chartType: 'FilePath'
                 chartPath: './helm-chart'
                 releaseName: 'appointments'
                 valueFile: './helm-chart/values-prod.yaml'
                 overrideValues: |
                   image.repository=embassyappointmentsacr.azurecr.io/embassy-appointments/app
                   image.tag=$(Build.BuildId)
                   image.pullPolicy=IfNotPresent
                 install: true
                 waitForExecution: true
             
             # Verify deployment
             - task: Kubernetes@1
               displayName: 'Verify deployment'
               inputs:
                 connectionType: 'Kubernetes Service Connection'
                 kubernetesServiceEndpoint: 'AKS-Connection'
                 namespace: 'embassy-appointments'
                 command: 'get'
                 arguments: 'pods'
             
             # Check rollout status
             - script: |
                 kubectl rollout status deployment/appointments-embassy-appointments \
                   -n embassy-appointments \
                   --timeout=5m
               displayName: 'Check rollout status'
   ```

   **How Helm Deployment Works**:
   
   a. **Helm upgrade command** is executed with:
      - `--install` flag: Creates release if it doesn't exist
      - `-f values-prod.yaml`: Uses production configuration
      - `--set image.tag=$(Build.BuildId)`: Overrides image tag with build number
   
   b. **Helm processes templates**:
      - Reads `helm-chart/templates/deployment.yaml`
      - Substitutes values from `values-prod.yaml` and overrides
      - Generates Kubernetes manifests
   
   c. **Kubernetes applies changes**:
      - Creates new ReplicaSet with updated image tag
      - Starts new pods with new image from ACR
      - Performs rolling update (old pods terminate as new pods become ready)
      - Routes traffic to new pods once health checks pass
   
   d. **AKS authenticates to ACR**:
      - Uses AKS managed identity or service principal
      - Automatically configured with `az aks update --attach-acr`
      - No imagePullSecrets needed in deployment

3. **Monitor deployment**:
   ```bash
   # From local machine or Azure Cloud Shell
   kubectl rollout status deployment appointments-embassy-appointments \
     -n embassy-appointments
   
   # Watch pods update in real-time
   kubectl get pods -n embassy-appointments -w
   
   # Check deployment events
   kubectl describe deployment appointments-embassy-appointments \
     -n embassy-appointments
   ```

**Complete Pipeline Example** (`azure-pipelines.yml`):
```yaml
trigger:
  branches:
    include:
    - main
    - develop

variables:
  dockerRegistry: 'embassyappointmentsacr.azurecr.io'
  imageRepository: 'embassy-appointments/app'
  helmChartPath: './helm-chart'
  kubernetesNamespace: 'embassy-appointments'
  azureSubscription: 'Azure-Subscription-Connection'
  aksResourceGroup: 'embassy-appointments-rg'
  aksClusterName: 'embassy-appointments-aks'

stages:
- stage: Test
  displayName: 'Run Tests'
  jobs:
  - job: UnitTests
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: UsePythonVersion@0
      inputs:
        versionSpec: '3.11'
    
    - script: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        pip install pytest pytest-cov pytest-html
      displayName: 'Install dependencies'
    
    - script: |
        pytest tests/ \
          --cov=. \
          --cov-report=xml \
          --cov-report=html \
          --junitxml=test-results.xml
      displayName: 'Run tests with coverage'
    
    - task: PublishTestResults@2
      condition: succeededOrFailed()
      inputs:
        testResultsFiles: 'test-results.xml'
        testRunTitle: 'Python Unit Tests'
    
    - task: PublishCodeCoverageResults@1
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: 'coverage.xml'

- stage: Build
  displayName: 'Build and Push Image'
  dependsOn: Test
  condition: succeeded()
  jobs:
  - job: BuildPushImage
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: Docker@2
      displayName: 'Build Docker image'
      inputs:
        command: 'build'
        repository: '$(imageRepository)'
        dockerfile: 'Dockerfile'
        tags: |
          $(Build.BuildId)
          latest
    
    - task: Docker@2
      displayName: 'Push to ACR'
      inputs:
        command: 'push'
        containerRegistry: 'ACR-ServiceConnection'
        repository: '$(imageRepository)'
        tags: |
          $(Build.BuildId)
          latest

- stage: DeployProduction
  displayName: 'Deploy to AKS Production'
  dependsOn: Build
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployAKS
    displayName: 'Deploy to AKS'
    environment: 'production-aks'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - checkout: self
          
          - task: HelmInstaller@1
            displayName: 'Install Helm 3.12.0'
            inputs:
              helmVersionToInstall: '3.12.0'
          
          - task: AzureCLI@2
            displayName: 'Configure kubectl for AKS'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az aks get-credentials \
                  --resource-group $(aksResourceGroup) \
                  --name $(aksClusterName) \
                  --overwrite-existing
                
                # Verify connection
                kubectl cluster-info
                kubectl get nodes
          
          - task: HelmDeploy@0
            displayName: 'Helm upgrade release'
            inputs:
              connectionType: 'Azure Resource Manager'
              azureSubscription: '$(azureSubscription)'
              azureResourceGroup: '$(aksResourceGroup)'
              kubernetesCluster: '$(aksClusterName)'
              namespace: '$(kubernetesNamespace)'
              command: 'upgrade'
              chartType: 'FilePath'
              chartPath: '$(helmChartPath)'
              releaseName: 'appointments'
              valueFile: '$(helmChartPath)/values-prod.yaml'
              overrideValues: |
                image.repository=$(dockerRegistry)/$(imageRepository)
                image.tag=$(Build.BuildId)
                image.pullPolicy=IfNotPresent
                replicaCount=3
              install: true
              waitForExecution: true
              arguments: '--timeout 10m --create-namespace'
          
          - task: Kubernetes@1
            displayName: 'Verify deployment'
            inputs:
              connectionType: 'Azure Resource Manager'
              azureSubscriptionEndpoint: '$(azureSubscription)'
              azureResourceGroup: '$(aksResourceGroup)'
              kubernetesCluster: '$(aksClusterName)'
              namespace: '$(kubernetesNamespace)'
              command: 'get'
              arguments: 'all'
          
          - script: |
              echo "Waiting for rollout to complete..."
              kubectl rollout status deployment/appointments-embassy-appointments \
                -n $(kubernetesNamespace) \
                --timeout=5m
              
              echo "Checking pod health..."
              kubectl get pods -n $(kubernetesNamespace) -l app.kubernetes.io/name=embassy-appointments
              
              echo "Deployment successful!"
            displayName: 'Monitor rollout status'
```

**Pipeline Prerequisites**:

Before running the pipeline, configure these in Azure DevOps:

1. **Service Connections**:
   - **ACR-ServiceConnection**: Docker Registry connection to ACR
   - **Azure-Subscription-Connection**: Azure Resource Manager connection

2. **Create ACR Service Connection**:
   - Go to Project Settings → Service connections → New service connection
   - Select "Docker Registry"
   - Registry type: "Azure Container Registry"
   - Select subscription and ACR: `embassyappointmentsacr`
   - Name: `ACR-ServiceConnection`

3. **Create Azure Subscription Connection**:
   - Service connection type: "Azure Resource Manager"
   - Authentication: Service Principal (automatic)
   - Scope: Subscription or Resource Group
   - Name: `Azure-Subscription-Connection`

4. **Grant AKS Access to ACR**:
   ```bash
   az aks update \
     --resource-group embassy-appointments-rg \
     --name embassy-appointments-aks \
     --attach-acr embassyappointmentsacr
   ```

5. **Create Environment** (optional, for approvals):
   - Go to Pipelines → Environments → New environment
   - Name: `production-aks`
   - Add approval checks if desired

---

**Manual Deployment**:
```bash
# 1. Build and tag image
docker build -t embassyappointmentsacr.azurecr.io/appointments:1.0.1 .

# 2. Push to ACR
az acr login --name embassyappointmentsacr
docker push embassyappointmentsacr.azurecr.io/appointments:1.0.1

# 3. Update Helm deployment
helm upgrade appointments ./helm-chart \
  -f helm-chart/values-prod.yaml \
  --set image.tag=1.0.1 \
  -n embassy-appointments

# 4. Verify rollout
kubectl rollout status deployment appointments-embassy-appointments \
  -n embassy-appointments

# 5. Check pod health
kubectl get pods -n embassy-appointments
```

**Rollback if Issues**:
```bash
# View rollout history
kubectl rollout history deployment appointments-embassy-appointments \
  -n embassy-appointments

# Rollback to previous version
kubectl rollout undo deployment appointments-embassy-appointments \
  -n embassy-appointments

# Or rollback to specific revision
kubectl rollout undo deployment appointments-embassy-appointments \
  --to-revision=2 \
  -n embassy-appointments
```

---

### GCP Production Updates

**CI/CD with Cloud Build (Recommended)**:

1. **Push code to GitHub**:
   ```bash
   git add .
   git commit -m "feat: add new feature"
   git push origin main
   ```

2. **Cloud Build trigger executes**:
   - Runs tests
   - Builds Docker image
   - Pushes to Artifact Registry
   - Deploys to GKE using Helm

3. **Monitor deployment**:
   ```bash
   kubectl rollout status deployment appointments-embassy-appointments \
     -n embassy-appointments
   ```

**Manual Deployment**:
```bash
# 1. Build and tag image
docker build -t us-central1-docker.pkg.dev/embassy-appointments/appointments/app:1.0.1 .

# 2. Push to Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push us-central1-docker.pkg.dev/embassy-appointments/appointments/app:1.0.1

# 3. Update Helm deployment
helm upgrade appointments ./helm-chart \
  -f helm-chart/values-gcp.yaml \
  --set image.tag=1.0.1 \
  -n embassy-appointments

# 4. Verify rollout
kubectl rollout status deployment appointments-embassy-appointments \
  -n embassy-appointments
```

---

### Blue-Green Deployment (Advanced)

For critical updates with instant rollback capability:

```bash
# 1. Deploy new version (green) alongside existing (blue)
helm install appointments-green ./helm-chart \
  -f helm-chart/values-prod.yaml \
  --set image.tag=2.0.0 \
  --set fullnameOverride=appointments-green \
  -n embassy-appointments

# 2. Test green deployment
kubectl port-forward -n embassy-appointments svc/appointments-green 8080:80
# Test at http://localhost:8080

# 3. Switch ingress to green deployment
kubectl patch ingress appointments-embassy-appointments \
  -n embassy-appointments \
  -p '{"spec":{"rules":[{"host":"appointments.yourdomain.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"appointments-green","port":{"number":80}}}}]}}]}}'

# 4. Monitor production traffic

# 5. Remove blue deployment if successful
helm uninstall appointments -n embassy-appointments
```

---

## Configuration Management

### Configuration Types

**1. Non-Sensitive Configuration (ConfigMap)**:
- Application settings
- Environment-specific URLs
- Feature flags
- Logging levels

**2. Sensitive Configuration (Secret)**:
- API keys
- Database passwords
- SSL/TLS certificates
- OAuth tokens

---

### ConfigMap Management

**View Current ConfigMap**:
```bash
kubectl get configmap -n embassy-appointments
kubectl describe configmap appointments-embassy-appointments-config -n embassy-appointments
```

**Update ConfigMap**:

**Method 1: Edit directly**:
```bash
kubectl edit configmap appointments-embassy-appointments-config -n embassy-appointments
```

**Method 2: Update via Helm**:
```yaml
# helm-chart/values.yaml or values-prod.yaml
config:
  FLASK_ENV: production
  LOG_LEVEL: INFO
  MAX_APPOINTMENTS_PER_DAY: "50"
  ENABLE_NOTIFICATIONS: "true"
```

```bash
helm upgrade appointments ./helm-chart \
  -f helm-chart/values-prod.yaml \
  -n embassy-appointments
```

**Method 3: Create from file**:
```bash
kubectl create configmap appointments-config \
  --from-file=app.config \
  -n embassy-appointments \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Apply Changes**:
```bash
# ConfigMap changes require pod restart
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments
```

---

### Secret Management

**View Secrets** (base64 encoded):
```bash
kubectl get secrets -n embassy-appointments
kubectl get secret appointments-embassy-appointments-secret \
  -n embassy-appointments -o yaml
```

**Decode Secret**:
```bash
kubectl get secret appointments-embassy-appointments-secret \
  -n embassy-appointments \
  -o jsonpath='{.data.SECRET_KEY}' | base64 --decode
```

---

### Local Development (KIND)

**Update Secret**:
```bash
# Create new secret value
echo -n "new-secret-value" | base64

# Edit secret
kubectl edit secret appointments-embassy-appointments-secret -n embassy-appointments

# Or delete and recreate
kubectl delete secret appointments-embassy-appointments-secret -n embassy-appointments
kubectl create secret generic appointments-embassy-appointments-secret \
  --from-literal=SECRET_KEY="new-secret-value" \
  --from-literal=API_KEY="new-api-key" \
  -n embassy-appointments

# Restart pods to pick up new secret
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments
```

---

### Azure Production (Key Vault)

**Store Secret in Key Vault**:
```bash
# Create secret
az keyvault secret set \
  --vault-name embassy-appointments-kv \
  --name app-secret-key \
  --value "super-secret-value-12345"

# List secrets
az keyvault secret list --vault-name embassy-appointments-kv
```

**Access from AKS** (using CSI Driver):

Secrets are automatically synced to Kubernetes via the CSI driver:
```yaml
# Already configured in helm-chart/templates/secret.yaml
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "azure-keyvault"
```

**Update Secret**:
```bash
# 1. Update in Key Vault
az keyvault secret set \
  --vault-name embassy-appointments-kv \
  --name app-secret-key \
  --value "new-secret-value"

# 2. Restart pods to pick up new value (CSI driver syncs every 2 minutes by default)
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments
```

---

### GCP Production (Secret Manager)

**Store Secret**:
```bash
# Create secret
echo -n "super-secret-value-12345" | \
  gcloud secrets create app-secret-key --data-file=-

# List secrets
gcloud secrets list

# Add new version
echo -n "new-secret-value" | \
  gcloud secrets versions add app-secret-key --data-file=-
```

**Access from GKE** (using Workload Identity):

Application pods use Workload Identity to access Secret Manager:
```yaml
# Already configured in helm-chart/values-gcp.yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: appointments-sa@PROJECT_ID.iam.gserviceaccount.com
```

**Update Secret**:
```bash
# 1. Create new version in Secret Manager
echo -n "new-secret-value" | \
  gcloud secrets versions add app-secret-key --data-file=-

# 2. Restart pods to pick up new version
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments
```

---

### Environment-Specific Configuration

**Development** (`values-dev.yaml`):
```yaml
replicaCount: 1
resources:
  requests:
    cpu: 100m
    memory: 128Mi
image:
  pullPolicy: Never  # Use local images
persistence:
  size: 500Mi
```

**Production** (`values-prod.yaml`):
```yaml
replicaCount: 3
resources:
  requests:
    cpu: 500m
    memory: 512Mi
image:
  pullPolicy: IfNotPresent  # Pull from registry
persistence:
  size: 10Gi
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

**Deploy with Specific Environment**:
```bash
# Development
helm upgrade appointments ./helm-chart -f helm-chart/values-dev.yaml

# Production
helm upgrade appointments ./helm-chart -f helm-chart/values-prod.yaml

# Override specific values
helm upgrade appointments ./helm-chart \
  -f helm-chart/values-prod.yaml \
  --set replicaCount=5 \
  --set image.tag=1.2.3
```

---

## Monitoring and Logging

### Application Health Checks

**Liveness Probe**: Checks if application is running
```bash
curl http://appointments.local/health
# Expected: {"status": "healthy"}
```

**Readiness Probe**: Checks if application is ready to serve traffic
```bash
curl http://appointments.local/ready
# Expected: {"status": "ready"}
```

---

### View Logs

**Recent Logs**:
```bash
# All pods
kubectl logs -n embassy-appointments -l app.kubernetes.io/name=embassy-appointments --tail=100

# Specific pod
kubectl logs -n embassy-appointments <pod-name> --tail=100

# Follow logs (real-time)
kubectl logs -n embassy-appointments -l app.kubernetes.io/name=embassy-appointments -f

# Previous crashed container
kubectl logs -n embassy-appointments <pod-name> --previous
```

**Azure Monitor Logs**:
```bash
# Query using Azure CLI
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "ContainerLog | where PodName contains 'appointments' | take 100"
```

**GCP Cloud Logging**:
```bash
gcloud logging read \
  "resource.type=k8s_container AND resource.labels.namespace_name=embassy-appointments" \
  --limit=100 \
  --format=json
```

---

### Metrics and Monitoring

**Kubernetes Metrics**:
```bash
# Pod resource usage
kubectl top pods -n embassy-appointments

# Node resource usage
kubectl top nodes

# Detailed pod info
kubectl describe pod <pod-name> -n embassy-appointments
```

**Prometheus Queries** (if ServiceMonitor enabled):
```promql
# Request rate
rate(http_requests_total{namespace="embassy-appointments"}[5m])

# Error rate
rate(http_requests_total{namespace="embassy-appointments",status=~"5.."}[5m])

# Pod CPU usage
container_cpu_usage_seconds_total{namespace="embassy-appointments"}
```

---

## Backup and Recovery

### Database Backup (SQLite)

**Manual Backup**:
```bash
# Copy database from pod
kubectl cp embassy-appointments/<pod-name>:/data/appointments.db \
  ./backups/appointments-$(date +%Y%m%d).db

# Verify backup
file ./backups/appointments-*.db
```

**Scheduled Backup** (CronJob):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: embassy-appointments
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine:latest
            command:
            - sh
            - -c
            - |
              cp /data/appointments.db /backup/appointments-$(date +%Y%m%d).db
            volumeMounts:
            - name: data
              mountPath: /data
            - name: backup
              mountPath: /backup
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: appointments-data
          - name: backup
            persistentVolumeClaim:
              claimName: appointments-backup
          restartPolicy: OnFailure
```

---

### Database Restore

**From Local Backup**:
```bash
# Copy backup to pod
kubectl cp ./backups/appointments-20240115.db \
  embassy-appointments/<pod-name>:/data/appointments.db

# Restart application
kubectl rollout restart deployment appointments-embassy-appointments \
  -n embassy-appointments
```

**From Cloud Storage** (Azure):
```bash
# Download from Azure Blob Storage
az storage blob download \
  --account-name appointmentsbackup \
  --container-name backups \
  --name appointments-20240115.db \
  --file appointments.db

# Copy to pod
kubectl cp appointments.db \
  embassy-appointments/<pod-name>:/data/appointments.db
```

---

## Troubleshooting

### Common Issues

**1. Pods not starting**:
```bash
# Check pod status
kubectl get pods -n embassy-appointments

# Describe pod for events
kubectl describe pod <pod-name> -n embassy-appointments

# Check logs
kubectl logs <pod-name> -n embassy-appointments

# Common causes:
# - Image pull errors (check image name/tag)
# - Resource limits (check node capacity)
# - Volume mount issues (check PVC status)
```

**2. Application not accessible**:
```bash
# Check ingress
kubectl get ingress -n embassy-appointments
kubectl describe ingress appointments-embassy-appointments -n embassy-appointments

# Check service
kubectl get svc -n embassy-appointments
kubectl describe svc appointments-embassy-appointments -n embassy-appointments

# Test service directly
kubectl port-forward -n embassy-appointments svc/appointments-embassy-appointments 8080:80
curl http://localhost:8080

# Common causes:
# - DNS not configured
# - Ingress controller not running
# - Service selector mismatch
```

**3. Database connection issues**:
```bash
# Check PVC
kubectl get pvc -n embassy-appointments
kubectl describe pvc appointments-data -n embassy-appointments

# Check if database file exists
kubectl exec -it <pod-name> -n embassy-appointments -- ls -lh /data/

# Common causes:
# - PVC not bound
# - Incorrect volume mount path
# - File permissions
```

**4. Configuration not updating**:
```bash
# Verify ConfigMap/Secret changes
kubectl get configmap appointments-embassy-appointments-config -n embassy-appointments -o yaml
kubectl get secret appointments-embassy-appointments-secret -n embassy-appointments -o yaml

# Restart deployment to pick up changes
kubectl rollout restart deployment appointments-embassy-appointments -n embassy-appointments

# Verify pods are using new config
kubectl exec -it <pod-name> -n embassy-appointments -- env | grep FLASK
```

---

### Debugging Tools

**Interactive Shell**:
```bash
kubectl exec -it <pod-name> -n embassy-appointments -- /bin/sh
```

**Network Debugging**:
```bash
# Deploy debug pod
kubectl run debug --image=nicolaka/netshoot -it --rm -n embassy-appointments

# Inside debug pod:
nslookup appointments-embassy-appointments
curl http://appointments-embassy-appointments
ping appointments-embassy-appointments
```

**Events**:
```bash
# Cluster events
kubectl get events -n embassy-appointments --sort-by='.lastTimestamp'

# Watch events in real-time
kubectl get events -n embassy-appointments --watch
```

---

## Best Practices

### Security
- ✅ Never commit secrets to version control
- ✅ Use Key Vault/Secret Manager for production secrets
- ✅ Rotate secrets regularly (every 90 days)
- ✅ Use RBAC to limit access to secrets
- ✅ Enable network policies to restrict pod communication

### Configuration
- ✅ Keep environment-specific values in separate files
- ✅ Use ConfigMaps for non-sensitive configuration
- ✅ Document all configuration options
- ✅ Validate configuration before deployment
- ✅ Version control Helm values files

### Deployments
- ✅ Always test in development before production
- ✅ Use CI/CD pipelines for consistency
- ✅ Implement health checks (liveness/readiness)
- ✅ Set appropriate resource requests/limits
- ✅ Monitor deployments and set up alerts
- ✅ Have rollback plan ready

### Monitoring
- ✅ Centralize logs for easy searching
- ✅ Set up alerts for critical errors
- ✅ Monitor resource usage trends
- ✅ Track application metrics (requests, latency, errors)
- ✅ Review logs and metrics regularly

---

## Support and Contact

For issues or questions:
- **Documentation**: See `Documentation/` folder
- **Troubleshooting**: See `Documentation/TROUBLESHOOTING-NGINX-INGRESS.md`
- **Helm Guide**: See `Documentation/HELM-CHART-GUIDE.md`
- **Repository**: https://github.com/SinaDadvand/appointment_app
