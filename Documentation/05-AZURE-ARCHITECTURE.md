# Azure Architecture Design

## Overview
Cloud-native architecture for deploying the Embassy Appointment System on Microsoft Azure with high availability, security, and scalability.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Internet Users                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure Front Door / CDN                            │
│  - Global load balancing                                             │
│  - WAF (Web Application Firewall)                                    │
│  - DDoS Protection                                                   │
│  - SSL/TLS Termination                                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure Application Gateway                         │
│  - Regional load balancing                                           │
│  - WAF tier 2                                                        │
│  - URL-based routing                                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
┌──────────────────┐            ┌──────────────────┐
│   Region 1       │            │   Region 2       │
│   (Primary)      │            │   (DR/Failover)  │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Azure Kubernetes Service (AKS) Cluster                  │
│                                                                       │
│  ┌────────────────────────────────────────────────────────┐         │
│  │                 Ingress Controller                      │         │
│  │              (NGINX or App Gateway Ingress)             │         │
│  └────────────────────┬───────────────────────────────────┘         │
│                       │                                              │
│         ┌─────────────┴─────────────┐                               │
│         ▼                           ▼                                │
│  ┌──────────────┐          ┌──────────────┐                         │
│  │   Pod 1      │          │   Pod 2      │  ... Pod 3-10           │
│  │              │          │              │  (Auto-scaled)           │
│  │  App + DB    │          │  App + DB    │                         │
│  │  Container   │          │  Container   │                         │
│  └──────┬───────┘          └──────┬───────┘                         │
│         │                         │                                  │
│         └────────────┬────────────┘                                 │
│                      │                                               │
│                      ▼                                               │
│         ┌─────────────────────────┐                                 │
│         │   Persistent Volume     │                                 │
│         │   (Azure Disk/Files)    │                                 │
│         └─────────────────────────┘                                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌────────────────────────┐      ┌────────────────────────┐
│  Azure Database for    │      │   Azure Key Vault      │
│  PostgreSQL (Optional) │      │  - Secrets             │
│  - Flexible Server     │      │  - Certificates        │
│  - HA enabled          │      │  - API Keys            │
│  - Read replicas       │      └────────────────────────┘
└────────────────────────┘
            │
            ▼
┌────────────────────────┐
│  Azure Backup          │
│  - Database backups    │
│  - PV snapshots        │
└────────────────────────┘
```

---

## Azure Services Used

### 1. **Azure Kubernetes Service (AKS)**
**Purpose**: Container orchestration platform
**Configuration**:
- **SKU**: Standard tier
- **Node pools**: 
  - System pool: 2 nodes (Standard_D2s_v3)
  - User pool: 3-10 nodes with autoscaling (Standard_D4s_v3)
- **Availability Zones**: Enabled across 3 zones
- **Network Plugin**: Azure CNI
- **Network Policy**: Azure Network Policy or Calico
- **Auto-upgrade**: Enabled with maintenance window
- **Monitoring**: Azure Monitor for containers

**Why**:
- Managed Kubernetes service
- Built-in high availability
- Seamless Azure integration
- Auto-scaling and auto-repair

---

### 2. **Azure Container Registry (ACR)**
**Purpose**: Private Docker image repository
**Configuration**:
- **SKU**: Premium (for geo-replication)
- **Geo-replication**: Primary + 1 secondary region
- **Content trust**: Enabled
- **Vulnerability scanning**: Microsoft Defender for Containers
- **Private endpoint**: VNet integration

**Why**:
- Secure image storage
- Fast image pulls (regional)
- Built-in security scanning
- Azure AD integration

---

### 3. **Azure Application Gateway**
**Purpose**: Layer 7 load balancer with WAF
**Configuration**:
- **SKU**: WAF_v2
- **Autoscaling**: 2-10 instances
- **WAF**: OWASP 3.2 ruleset
- **SSL/TLS**: End-to-end encryption
- **Health probes**: Custom probes for /health endpoint

**Alternative**: Application Gateway Ingress Controller (AGIC) for direct AKS integration

**Why**:
- Advanced load balancing
- Web Application Firewall
- SSL offloading
- URL-based routing

---

### 4. **Azure Front Door** (Optional - Global deployment)
**Purpose**: Global load balancer and CDN
**Configuration**:
- **SKU**: Premium (includes WAF)
- **Backend pools**: Multiple AKS clusters
- **Routing**: Priority-based failover
- **Caching**: Static assets
- **WAF**: Global policies

**Why**:
- Multi-region failover
- Global load balancing
- DDoS protection (Layer 3-7)
- Performance optimization

---

### 5. **Azure Key Vault**
**Purpose**: Secrets and certificate management
**Configuration**:
- **SKU**: Premium (HSM-backed)
- **Access**: Managed Identity (AKS workload identity)
- **Soft delete**: Enabled
- **Purge protection**: Enabled
- **RBAC**: Azure AD integrated

**Integration**: 
- Secrets Store CSI Driver for Kubernetes
- Or Azure Key Vault Provider for Secrets Store CSI Driver

**Why**:
- Centralized secret management
- Audit logging
- Certificate auto-rotation
- HSM protection

---

### 6. **Azure Database for PostgreSQL** (Optional upgrade from SQLite)
**Purpose**: Managed database service
**Configuration**:
- **Tier**: Flexible Server
- **Compute**: Burstable (B2s) to General Purpose
- **HA**: Zone-redundant HA
- **Backup**: Automated daily backups, 35-day retention
- **Read replicas**: 1-2 replicas for read scaling
- **Private endpoint**: VNet integration

**Why**:
- Fully managed
- Automatic backups
- High availability
- Better performance for production

---

### 7. **Azure Monitor & Log Analytics**
**Purpose**: Monitoring and logging
**Configuration**:
- **Container Insights**: Enabled on AKS
- **Log Analytics Workspace**: Centralized logging
- **Application Insights**: Application performance monitoring
- **Alerts**: CPU, memory, error rate thresholds
- **Dashboards**: Custom metrics and KPIs

**Metrics Collected**:
- Container CPU/Memory
- Pod health and restarts
- Application logs
- HTTP request metrics
- Custom business metrics

**Why**:
- Comprehensive monitoring
- Troubleshooting capabilities
- Performance analytics
- Cost management

---

### 8. **Azure Backup & Site Recovery**
**Purpose**: Disaster recovery and backup
**Configuration**:
- **Azure Backup**: 
  - Database backups (point-in-time recovery)
  - AKS persistent volume snapshots
- **Azure Site Recovery**: 
  - VM replication (if using VMs)
  - Cross-region disaster recovery

**Why**:
- Data protection
- Compliance requirements
- Quick recovery (RPO/RTO)

---

### 9. **Azure Virtual Network (VNet)**
**Purpose**: Network isolation and security
**Configuration**:
- **Address space**: 10.0.0.0/16
- **Subnets**:
  - AKS system: 10.0.0.0/20 (4096 IPs)
  - AKS user: 10.0.16.0/20 (4096 IPs)
  - App Gateway: 10.0.32.0/24 (256 IPs)
  - Database: 10.0.33.0/24 (256 IPs)
  - Private endpoints: 10.0.34.0/24
- **NSGs**: Network Security Groups on each subnet
- **Service endpoints**: For Azure services
- **Private endpoints**: ACR, Key Vault, Database

**Why**:
- Network isolation
- Security boundaries
- Private connectivity
- No public internet exposure for backend

---

### 10. **Azure Active Directory (Azure AD)**
**Purpose**: Identity and access management
**Configuration**:
- **AKS Integration**: Azure AD-integrated RBAC
- **Managed Identity**: System-assigned for AKS
- **Workload Identity**: Pod-level identities
- **Conditional Access**: MFA for admin access

**Why**:
- Centralized authentication
- Fine-grained RBAC
- No credential management
- Audit trail

---

### 11. **Azure DNS**
**Purpose**: Domain name management
**Configuration**:
- **Public zone**: embassy.gov
- **Records**: A/CNAME for appointments.embassy.gov
- **TTL**: 300 seconds
- **Traffic Manager** (optional): For multi-region routing

**Why**:
- Reliable DNS
- Integration with Azure services
- Health-based routing

---

### 12. **Microsoft Defender for Cloud**
**Purpose**: Security posture management
**Configuration**:
- **Defender for Containers**: Enabled
- **Defender for Key Vault**: Enabled
- **Defender for Databases**: Enabled
- **Security recommendations**: Auto-remediation
- **Compliance**: PCI-DSS, HIPAA (if needed)

**Why**:
- Threat detection
- Vulnerability management
- Compliance monitoring
- Security recommendations

---

## Network Architecture

### Traffic Flow

1. **User Request** → Azure Front Door (global entry point)
2. **Front Door** → Application Gateway (regional LB)
3. **App Gateway** → AKS Ingress Controller (NGINX)
4. **Ingress** → Service (ClusterIP)
5. **Service** → Pods (application containers)
6. **Pods** → Azure Database for PostgreSQL (via private endpoint)
7. **Pods** → Azure Key Vault (for secrets, via workload identity)

### Security Layers

1. **Layer 1**: DDoS Protection (Azure DDoS Standard)
2. **Layer 2**: WAF at Front Door (global threats)
3. **Layer 3**: WAF at Application Gateway (regional threats)
4. **Layer 4**: Network Security Groups (subnet-level)
5. **Layer 5**: Kubernetes Network Policies (pod-level)
6. **Layer 6**: Azure AD authentication
7. **Layer 7**: Application-level security (input validation)

---

## High Availability Design

### Multi-Zone Deployment
- AKS nodes distributed across 3 availability zones
- Database with zone-redundant HA
- Load balancers across zones

### Auto-Scaling
- **Horizontal Pod Autoscaler (HPA)**: 3-10 pods based on CPU/memory
- **Cluster Autoscaler**: Add/remove nodes based on demand
- **Application Gateway**: 2-10 instances autoscaling

### Health Checks
- **Liveness probes**: Restart unhealthy pods
- **Readiness probes**: Remove from load balancer
- **Startup probes**: Allow slow starting apps

### Disaster Recovery
- **RTO**: < 15 minutes (Recovery Time Objective)
- **RPO**: < 5 minutes (Recovery Point Objective)
- **Strategy**: Active-passive across regions
- **Failover**: Automatic via Azure Front Door

---

## Cost Optimization

### Estimated Monthly Cost (Production)

| Service | Configuration | Est. Cost (USD) |
|---------|--------------|-----------------|
| AKS (3-5 nodes) | Standard_D4s_v3 | $300-500 |
| Application Gateway WAF | WAF_v2, 2 instances | $250 |
| Azure Container Registry | Premium | $40 |
| Azure Database PostgreSQL | Flexible, 2vCore HA | $150-250 |
| Azure Key Vault | Premium | $10 |
| Azure Monitor | Standard | $100 |
| Storage (disks, backups) | Premium SSD | $50 |
| **Total** | | **$900-1,200/month** |

### Cost Saving Tips
1. Use **Azure Reservations** (1-3 year commitment) for 40-60% savings
2. **Spot instances** for non-critical workloads
3. **Auto-shutdown** development environments
4. **Right-size** node pools based on actual usage
5. **Azure Hybrid Benefit** if you have licenses

---

## Deployment Steps (High-Level)

### 1. Prerequisites
```bash
# Install Azure CLI
az login
az account set --subscription "Your-Subscription"

# Install kubectl and helm
# Already done in local setup
```

### 2. Create Resource Group
```bash
az group create \
  --name rg-embassy-appointments-prod \
  --location eastus
```

### 3. Create Azure Container Registry
```bash
az acr create \
  --resource-group rg-embassy-appointments-prod \
  --name acrembassynappointments \
  --sku Premium \
  --admin-enabled false

# Enable geo-replication
az acr replication create \
  --registry acrembassynappointments \
  --location westus
```

### 4. Create AKS Cluster
```bash
az aks create \
  --resource-group rg-embassy-appointments-prod \
  --name aks-embassy-appointments \
  --node-count 3 \
  --enable-managed-identity \
  --enable-addons monitoring \
  --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 10 \
  --network-plugin azure \
  --network-policy azure \
  --zones 1 2 3 \
  --attach-acr acrembassynappointments \
  --enable-aad \
  --enable-azure-rbac
```

### 5. Create Key Vault
```bash
az keyvault create \
  --name kv-embassy-appts \
  --resource-group rg-embassy-appointments-prod \
  --location eastus \
  --enable-rbac-authorization
```

### 6. Build and Push Image
```bash
# Login to ACR
az acr login --name acrembassynappointments

# Build and push
docker build -t acrembassynappointments.azurecr.io/embassy-appointments:1.0.0 .
docker push acrembassynappointments.azurecr.io/embassy-appointments:1.0.0
```

### 7. Deploy with Helm
```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group rg-embassy-appointments-prod \
  --name aks-embassy-appointments

# Install app
helm install appointments ./helm-chart \
  -f helm-chart/values-prod.yaml \
  -n embassy-appointments \
  --create-namespace \
  --set image.repository=acrembassynappointments.azurecr.io/embassy-appointments \
  --set image.tag=1.0.0
```

### 8. Configure Application Gateway Ingress (Optional)
```bash
# Install AGIC
az aks enable-addons \
  --resource-group rg-embassy-appointments-prod \
  --name aks-embassy-appointments \
  --addons ingress-appgw \
  --appgw-name appgw-embassy \
  --appgw-subnet-cidr "10.0.32.0/24"
```

---

## Security Best Practices

### 1. **Network Security**
- All backend services in private subnets
- No public IPs on pods
- NSGs on all subnets
- Private endpoints for PaaS services

### 2. **Identity & Access**
- Azure AD integration for human access
- Managed identities for service-to-service
- RBAC at cluster and namespace level
- Principle of least privilege

### 3. **Secrets Management**
- No secrets in code or environment variables
- Azure Key Vault for all secrets
- Automatic secret rotation
- Audit logging enabled

### 4. **Container Security**
- Vulnerability scanning in ACR
- Only signed images allowed
- Non-root containers
- Read-only root filesystem where possible
- Security policies (Azure Policy/OPA Gatekeeper)

### 5. **Data Protection**
- Encryption at rest (Azure Storage encryption)
- Encryption in transit (TLS 1.2+)
- Database backups encrypted
- Geo-redundant backups

---

## Monitoring & Alerting

### Key Metrics to Monitor
1. **Availability**: Uptime percentage, error rates
2. **Performance**: Response time, throughput
3. **Resource**: CPU, memory, disk usage
4. **Business**: Appointments created, conversion rate

### Alerts
1. Pod restart rate > 5 in 10 minutes
2. CPU usage > 80% for 5 minutes
3. Memory usage > 85% for 5 minutes
4. HTTP 5xx errors > 10 in 5 minutes
5. Disk usage > 80%
6. Certificate expiring in < 30 days

### Dashboards
- **Overview**: Health status, requests/sec, error rate
- **Performance**: Latency percentiles, throughput
- **Infrastructure**: Node health, pod distribution
- **Business**: Daily appointments, peak hours

---

## Compliance & Governance

### Azure Policy
- Require tags on resources
- Allowed VM/node sizes
- Required backup policies
- Network security rules

### Compliance Standards
- **PCI-DSS**: If handling payments
- **HIPAA**: If handling health data (medical exams)
- **SOC 2**: General security controls
- **FedRAMP**: If government deployment

### Audit Logging
- Azure Activity Log (all Azure operations)
- AKS audit logs (all K8s API calls)
- Application logs (business events)
- Security logs (authentication, authorization)

---

## CI/CD Integration

### Azure DevOps Pipeline
```yaml
# Example pipeline
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: Build
  jobs:
  - job: BuildAndPush
    steps:
    - task: Docker@2
      inputs:
        containerRegistry: 'ACR'
        repository: 'embassy-appointments'
        command: 'buildAndPush'
        
- stage: Deploy
  jobs:
  - job: HelmDeploy
    steps:
    - task: HelmDeploy@0
      inputs:
        command: 'upgrade'
        chartPath: './helm-chart'
        releaseName: 'appointments'
        namespace: 'embassy-appointments'
```

---

## Summary

This Azure architecture provides:

✅ **High Availability**: Multi-zone deployment, auto-scaling, health checks  
✅ **Security**: Multi-layer defense, private networking, secrets management  
✅ **Scalability**: Auto-scaling from 3 to 10+ pods based on demand  
✅ **Observability**: Comprehensive monitoring, logging, and alerting  
✅ **Cost-Effective**: ~$900-1,200/month with optimization opportunities  
✅ **Compliance-Ready**: Security controls, audit logs, encryption  
✅ **Production-Ready**: Automated deployments, disaster recovery, backups  

This architecture can handle thousands of concurrent users while maintaining security and compliance requirements for a government/embassy application.
