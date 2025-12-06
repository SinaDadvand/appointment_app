# Google Cloud Platform (GCP) Architecture Design

## Overview
Cloud-native architecture for deploying the Embassy Appointment System on Google Cloud Platform with high availability, security, and scalability.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Internet Users                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Cloud CDN + Cloud Armor                           │
│  - Global content delivery                                           │
│  - DDoS Protection                                                   │
│  - WAF rules                                                         │
│  - SSL/TLS Termination                                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Global HTTP(S) Load Balancer                            │
│  - Anycast IP                                                        │
│  - SSL certificates (Google-managed)                                 │
│  - URL maps and routing                                              │
└────────────────────────┬────────────────────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
┌──────────────────┐            ┌──────────────────┐
│   Region 1       │            │   Region 2       │
│   (us-central1)  │            │   (us-west1)     │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│         Google Kubernetes Engine (GKE) Autopilot Cluster             │
│                                                                       │
│  ┌────────────────────────────────────────────────────────┐         │
│  │         GKE Ingress (Cloud Load Balancing)             │         │
│  │              or NGINX Ingress Controller                │         │
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
│         │   (Persistent Disk)     │                                 │
│         └─────────────────────────┘                                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌────────────────────────┐      ┌────────────────────────┐
│  Cloud SQL for         │      │   Secret Manager       │
│  PostgreSQL (Optional) │      │  - Application secrets │
│  - HA configuration    │      │  - TLS certificates    │
│  - Read replicas       │      │  - API keys            │
│  - Automated backups   │      └────────────────────────┘
└────────────────────────┘
            │
            ▼
┌────────────────────────┐
│  Cloud Storage         │
│  - Database backups    │
│  - Application logs    │
└────────────────────────┘
```

---

## GCP Services Used

### 1. **Google Kubernetes Engine (GKE)**
**Purpose**: Managed Kubernetes cluster
**Configuration**:
- **Mode**: Autopilot (recommended) or Standard
- **Version**: Regular release channel
- **Locations**: 
  - **Regional**: us-central1 (primary), us-west1 (DR)
  - **Zones**: Across 3 zones per region
- **Node pools** (Standard mode):
  - System pool: e2-medium (2 vCPU, 4GB RAM) - 3 nodes
  - Application pool: e2-standard-4 (4 vCPU, 16GB RAM) - 3-10 nodes
- **Networking**: VPC-native cluster
- **Workload Identity**: Enabled
- **Binary Authorization**: Enabled (require signed images)
- **Monitoring**: Cloud Monitoring and Cloud Logging integrated

**Autopilot Benefits** (Recommended):
- No node management
- Pay per pod resource usage
- Auto-scaling and auto-repair built-in
- Security best practices by default
- Lower operational overhead

**Why**:
- Fully managed Kubernetes
- Automatic upgrades and patching
- Built-in high availability
- Seamless GCP integration
- Lower TCO with Autopilot

---

### 2. **Artifact Registry**
**Purpose**: Container image and artifact repository
**Configuration**:
- **Format**: Docker
- **Location**: Multi-region (us)
- **Encryption**: Customer-managed encryption keys (CMEK) optional
- **Vulnerability Scanning**: Enabled
- **Access**: IAM-based, Workload Identity
- **Retention**: Keep last 10 versions, delete older

**Why**:
- Next-generation container registry
- Multi-region replication
- Integrated vulnerability scanning
- Fine-grained IAM controls
- Better performance than GCR

---

### 3. **Cloud Load Balancing**
**Purpose**: Global HTTP(S) load balancer
**Configuration**:
- **Type**: External HTTP(S) Load Balancer
- **Backend**: GKE NEGs (Network Endpoint Groups)
- **SSL**: Google-managed certificates (auto-renewal)
- **Health checks**: Custom probes to /health endpoint
- **Session affinity**: Client IP or cookie-based
- **CDN**: Enabled for static content

**Features**:
- Anycast IP (single global IP)
- Cross-region load balancing
- Automatic failover
- Auto-scaling

**Why**:
- Global reach
- Built-in DDoS protection
- Automatic SSL certificate management
- Integrated with Cloud CDN

---

### 4. **Cloud Armor**
**Purpose**: DDoS protection and Web Application Firewall
**Configuration**:
- **Security policy**: Attached to load balancer
- **Rules**:
  - OWASP Top 10 protection
  - Rate limiting (100 req/min per IP)
  - Geo-blocking (allow specific countries)
  - IP allowlist/denylist
- **Adaptive Protection**: ML-based DDoS mitigation
- **Preview mode**: Test rules before enforcing

**Why**:
- Layer 7 DDoS protection
- Customizable WAF rules
- Protection at edge (before traffic reaches GKE)
- Integration with Cloud Logging

---

### 5. **Secret Manager**
**Purpose**: Secrets and sensitive data management
**Configuration**:
- **Replication**: Automatic across regions
- **Access**: Workload Identity from GKE
- **Versioning**: Enabled (keep last 10 versions)
- **Rotation**: Manual or automated via Cloud Functions
- **Audit**: Cloud Audit Logs enabled

**Integration**:
- External Secrets Operator (recommended)
- Or Secrets Store CSI Driver

**Secrets Stored**:
- Application secret keys
- Database passwords
- API keys
- TLS private keys

**Why**:
- Centralized secret management
- Automatic encryption (Google-managed keys)
- Fine-grained access control
- Audit trail
- Version management

---

### 6. **Cloud SQL for PostgreSQL** (Optional upgrade)
**Purpose**: Managed PostgreSQL database
**Configuration**:
- **Tier**: db-custom-2-4096 (2 vCPU, 4GB RAM) to start
- **HA**: Regional HA (automatic failover)
- **Backups**: 
  - Automated daily backups
  - Point-in-time recovery (7-day window)
  - Transaction logs
- **Read replicas**: 1-2 replicas for read scaling
- **Connectivity**: Private IP (VPC peering)
- **Maintenance**: Automated patches with window
- **Encryption**: At rest and in transit

**Why**:
- Fully managed
- Automatic failover (< 60 seconds)
- Point-in-time recovery
- Read replicas for scaling
- No operational overhead

---

### 7. **Cloud Monitoring & Cloud Logging**
**Purpose**: Observability platform
**Configuration**:
- **GKE Integration**: Automatic collection of:
  - Container logs
  - System logs
  - Audit logs
  - Metrics (CPU, memory, network)
- **Custom Metrics**: Application-level metrics
- **Uptime Checks**: External monitoring
- **Alerting Policies**:
  - Pod CPU > 80%
  - Error rate > 5%
  - Latency p95 > 500ms
- **Dashboards**: Pre-built GKE dashboards + custom
- **Log Router**: Export logs to Cloud Storage, BigQuery

**Cloud Trace & Profiler** (Optional):
- Distributed tracing
- Performance profiling

**Why**:
- Native GCP integration
- Rich query language
- Long-term log storage
- Trace and profile capabilities
- Cost-effective

---

### 8. **Cloud Storage**
**Purpose**: Object storage for backups and static assets
**Configuration**:
- **Buckets**:
  - `gs://embassy-appointments-backups`: Database backups
  - `gs://embassy-appointments-logs`: Long-term logs
- **Storage class**: Standard (frequently accessed)
- **Lifecycle policy**: Move to Nearline after 30 days, delete after 90
- **Versioning**: Enabled
- **Encryption**: Google-managed or CMEK
- **Access**: IAM + signed URLs

**Why**:
- Durable storage (11 9's)
- Cost-effective for backups
- Lifecycle management
- Global accessibility

---

### 9. **Virtual Private Cloud (VPC)**
**Purpose**: Network isolation
**Configuration**:
- **Network**: Custom mode VPC
- **Subnets**:
  - `gke-subnet`: 10.0.0.0/20 (GKE pods and nodes)
  - `services-subnet`: 10.1.0.0/20 (GKE services)
  - `db-subnet`: 10.2.0.0/24 (Cloud SQL)
- **Secondary ranges** (for GKE):
  - Pods: 10.10.0.0/16
  - Services: 10.20.0.0/16
- **Firewall Rules**:
  - Allow ingress from load balancer
  - Allow internal cluster communication
  - Deny all other ingress by default
- **Private Google Access**: Enabled
- **Cloud NAT**: For egress traffic from private nodes

**Why**:
- Network isolation
- Private cluster (no public node IPs)
- Controlled egress with Cloud NAT
- Fine-grained firewall rules

---

### 10. **Cloud IAM & Workload Identity**
**Purpose**: Authentication and authorization
**Configuration**:
- **GKE Workload Identity**: Enabled
  - Pods use GCP service accounts
  - No service account keys needed
- **IAM Roles**:
  - `roles/container.admin`: For CI/CD
  - `roles/artifactregistry.reader`: For GKE to pull images
  - `roles/secretmanager.secretAccessor`: For app to access secrets
  - `roles/cloudsql.client`: For app to connect to database
- **Custom Roles**: Principle of least privilege
- **Service Accounts**:
  - `gke-cluster-sa`: GKE cluster operations
  - `app-workload-sa`: Application workload

**Why**:
- No credential management
- Fine-grained permissions
- Audit trail
- Temporary tokens (auto-rotated)

---

### 11. **Cloud DNS**
**Purpose**: Domain name resolution
**Configuration**:
- **Zone type**: Public
- **Domain**: embassy.gov
- **Records**:
  - A record: appointments.embassy.gov → Load Balancer IP
  - AAAA record: IPv6 support
- **DNSSEC**: Enabled
- **TTL**: 300 seconds

**Why**:
- Fast, reliable DNS
- Global anycast network
- Integration with Load Balancer
- DNSSEC support

---

### 12. **Binary Authorization**
**Purpose**: Deploy-time security enforcement
**Configuration**:
- **Policy**: Require attestations
- **Attestors**: 
  - Vulnerability scan passed
  - Image signed by CI/CD
- **Enforcement**: Block unsigned images
- **Break-glass**: Emergency override capability

**Why**:
- Ensure only vetted images run
- Prevent supply chain attacks
- Compliance requirement
- Audit trail

---

### 13. **Cloud Build** (CI/CD)
**Purpose**: Build and deploy automation
**Configuration**:
- **Triggers**: On GitHub push to main
- **Steps**:
  1. Run tests
  2. Build Docker image
  3. Push to Artifact Registry
  4. Create attestation
  5. Deploy via Helm to GKE
- **Service account**: Limited permissions
- **Substitutions**: Dynamic variables

**Why**:
- Serverless CI/CD
- Native GCP integration
- Pay per build minute
- Artifact attestation

---

### 14. **Security Command Center**
**Purpose**: Security and compliance monitoring
**Configuration**:
- **Premium tier**: Advanced threat detection
- **Asset inventory**: All GCP resources
- **Findings**: Vulnerabilities, misconfigurations
- **Compliance**: CIS, PCI-DSS, HIPAA benchmarks
- **Notifications**: Security findings to email/Slack

**Why**:
- Centralized security view
- Threat detection
- Compliance monitoring
- Recommendations

---

## Network Architecture

### Traffic Flow

1. **User Request** → Cloud CDN + Cloud Armor (edge protection)
2. **Cloud Armor** → Global HTTP(S) Load Balancer (anycast IP)
3. **Load Balancer** → GKE Ingress or NGINX Ingress
4. **Ingress** → ClusterIP Service
5. **Service** → Pods (application containers)
6. **Pods** → Cloud SQL via Private IP
7. **Pods** → Secret Manager via Workload Identity

### Security Layers

1. **Layer 1**: Cloud Armor (DDoS, WAF at edge)
2. **Layer 2**: Load Balancer SSL/TLS termination
3. **Layer 3**: VPC firewall rules
4. **Layer 4**: GKE Network Policies (pod-to-pod)
5. **Layer 5**: Binary Authorization (image validation)
6. **Layer 6**: Workload Identity (service authentication)
7. **Layer 7**: Application-level validation

---

## High Availability Design

### Regional HA (Single Region)
- GKE cluster spans 3 zones
- Cloud SQL regional HA (automatic failover)
- Load balancer distributes across zones
- Persistent disks replicated across zones

### Multi-Regional HA (Production)
- GKE clusters in us-central1 and us-west1
- Global Load Balancer routes to nearest healthy region
- Cloud SQL cross-region replicas (read-only)
- Failover via health checks (automatic)

### Auto-Scaling
- **Horizontal Pod Autoscaler (HPA)**: 3-10 pods based on CPU/memory
- **Cluster Autoscaler**: Add/remove nodes automatically (Standard mode)
- **Autopilot**: Automatic pod-level scaling (Autopilot mode)

### Health Checks
- **Liveness**: Restart unhealthy containers
- **Readiness**: Remove from service rotation
- **Startup**: Grace period for slow starts
- **Load Balancer**: External health checks

### Disaster Recovery
- **RTO**: < 10 minutes (multi-region) or < 1 hour (single region restore)
- **RPO**: < 5 minutes (Cloud SQL transaction logs)
- **Strategy**: Active-active (multi-region) or active-passive
- **Backups**: Automated daily + transaction logs

---

## Cost Optimization

### Estimated Monthly Cost (Production - Single Region)

| Service | Configuration | Est. Cost (USD) |
|---------|--------------|-----------------|
| GKE Autopilot | ~10 pods, 4 vCPU, 16GB | $200-300 |
| GKE Standard | 3-5 nodes, e2-standard-4 | $150-250 |
| Cloud Load Balancer | 1 forwarding rule + bandwidth | $50-100 |
| Cloud Armor | 1 policy + rules | $20 |
| Artifact Registry | Storage + operations | $10-20 |
| Cloud SQL PostgreSQL | 2 vCPU, 4GB, HA | $100-150 |
| Secret Manager | ~20 secrets, 10K accesses | $5 |
| Cloud Monitoring/Logging | Standard usage | $50-100 |
| Cloud Storage | Backups, logs | $20-50 |
| Network Egress | Outbound traffic | $50-100 |
| **Total (Autopilot)** | | **$655-1,045/month** |
| **Total (Standard)** | | **$605-995/month** |

### Cost Saving Tips
1. **Committed Use Discounts**: 1 or 3-year commitments for 37-57% savings
2. **Sustained Use Discounts**: Automatic for long-running resources
3. **Preemptible VMs**: For non-critical workloads (80% discount)
4. **Autopilot**: Pay only for pod resources (no node overhead)
5. **Cloud Storage Lifecycle**: Move old backups to Coldline/Archive
6. **Egress Optimization**: Use Cloud CDN to reduce egress
7. **Rightsizing**: Recommendations from Cloud Monitoring

---

## Deployment Steps (High-Level)

### 1. Prerequisites
```bash
# Install gcloud CLI
gcloud auth login
gcloud config set project PROJECT_ID

# Install kubectl and helm
# Already done in local setup
```

### 2. Create VPC Network
```bash
gcloud compute networks create embassy-vpc \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

gcloud compute networks subnets create gke-subnet \
  --network=embassy-vpc \
  --region=us-central1 \
  --range=10.0.0.0/20 \
  --secondary-range pods=10.10.0.0/16,services=10.20.0.0/16
```

### 3. Create Artifact Registry
```bash
gcloud artifacts repositories create embassy-appointments \
  --repository-format=docker \
  --location=us \
  --description="Embassy Appointment System images"
```

### 4. Create GKE Cluster (Autopilot)
```bash
gcloud container clusters create-auto embassy-appointments \
  --region=us-central1 \
  --network=embassy-vpc \
  --subnetwork=gke-subnet \
  --cluster-secondary-range-name=pods \
  --services-secondary-range-name=services \
  --enable-master-authorized-networks \
  --master-authorized-networks=0.0.0.0/0 \
  --release-channel=regular
```

### 5. Create Cloud SQL Instance (Optional)
```bash
gcloud sql instances create embassy-db \
  --database-version=POSTGRES_15 \
  --tier=db-custom-2-4096 \
  --region=us-central1 \
  --network=embassy-vpc \
  --no-assign-ip \
  --availability-type=regional \
  --backup-start-time=03:00
```

### 6. Create Secrets in Secret Manager
```bash
echo -n "your-secret-key" | gcloud secrets create app-secret-key \
  --data-file=- \
  --replication-policy=automatic

# Grant access to workload identity
gcloud secrets add-iam-policy-binding app-secret-key \
  --member="serviceAccount:app-workload-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### 7. Build and Push Image
```bash
# Configure Docker for Artifact Registry
gcloud auth configure-docker us-docker.pkg.dev

# Build and push
docker build -t us-docker.pkg.dev/PROJECT_ID/embassy-appointments/app:1.0.0 .
docker push us-docker.pkg.dev/PROJECT_ID/embassy-appointments/app:1.0.0
```

### 8. Deploy with Helm
```bash
# Get GKE credentials
gcloud container clusters get-credentials embassy-appointments \
  --region=us-central1

# Create namespace
kubectl create namespace embassy-appointments

# Install app
helm install appointments ./helm-chart \
  -f helm-chart/values-prod.yaml \
  -n embassy-appointments \
  --set image.repository=us-docker.pkg.dev/PROJECT_ID/embassy-appointments/app \
  --set image.tag=1.0.0
```

### 9. Configure Load Balancer & Cloud Armor
```bash
# Cloud Armor security policy (created via console or terraform)
# Attach to backend service of load balancer

# Reserve static IP
gcloud compute addresses create appointments-ip \
  --global

# Create managed SSL certificate
gcloud compute ssl-certificates create appointments-ssl \
  --domains=appointments.embassy.gov \
  --global
```

---

## Security Best Practices

### 1. **Network Security**
- Private GKE cluster (no public node IPs)
- VPC-native networking
- Cloud NAT for controlled egress
- Firewall rules (default deny, explicit allow)
- Private Service Connect for Cloud SQL

### 2. **Identity & Access**
- Workload Identity (no service account keys)
- Least privilege IAM roles
- Regular access reviews
- MFA for human accounts
- Audit logging enabled

### 3. **Secrets Management**
- Secret Manager for all secrets
- Automatic encryption
- Version control
- Rotation policies
- Access logging

### 4. **Container Security**
- Binary Authorization (signed images only)
- Vulnerability scanning in Artifact Registry
- Non-root containers
- Read-only root filesystem
- Security Context constraints

### 5. **Data Protection**
- Encryption at rest (default)
- Encryption in transit (TLS 1.2+)
- Automated backups
- Point-in-time recovery
- Cross-region replication

---

## Monitoring & Alerting

### Key Metrics
1. **Availability**: SLI/SLO (target: 99.9% uptime)
2. **Latency**: p50, p95, p99 response times
3. **Error Rate**: 4xx, 5xx errors
4. **Saturation**: CPU, memory, network usage
5. **Traffic**: Requests per second

### Alerting Policies
1. **Critical**: 
   - Service unavailable (3 consecutive failures)
   - Error rate > 5% for 5 minutes
   - Database down
2. **Warning**:
   - CPU > 80% for 10 minutes
   - Memory > 85% for 10 minutes
   - Disk usage > 80%
3. **Info**:
   - New deployment
   - Configuration changes

### Dashboards
- **Overview**: Health, RPS, latency, errors
- **GKE**: Cluster health, pod status, node utilization
- **Application**: Business metrics, user activity
- **Database**: Connections, queries, replication lag

---

## Compliance & Governance

### Organization Policies
- Require VPC Service Controls
- Restrict public IP allocation
- Enforce OS Login
- Require encryption

### Compliance Standards
- **PCI-DSS**: Payment card data (if applicable)
- **HIPAA**: Healthcare data (medical exams)
- **SOC 2 Type II**: Security controls
- **FedRAMP**: Government deployment

### Audit Logging
- Admin Activity Logs (enabled by default)
- Data Access Logs (enabled for sensitive resources)
- System Event Logs
- Access Transparency (optional)

---

## CI/CD with Cloud Build

### cloudbuild.yaml Example
```yaml
steps:
  # Run tests
  - name: 'python:3.11-slim'
    entrypoint: 'sh'
    args:
      - '-c'
      - 'pip install -r requirements.txt && pytest tests/'
  
  # Build Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-docker.pkg.dev/$PROJECT_ID/embassy-appointments/app:$SHORT_SHA', '.']
  
  # Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-docker.pkg.dev/$PROJECT_ID/embassy-appointments/app:$SHORT_SHA']
  
  # Deploy with Helm
  - name: 'gcr.io/$PROJECT_ID/helm'
    args:
      - 'upgrade'
      - '--install'
      - 'appointments'
      - './helm-chart'
      - '-f'
      - 'helm-chart/values-prod.yaml'
      - '--set'
      - 'image.tag=$SHORT_SHA'
      - '-n'
      - 'embassy-appointments'
    env:
      - 'CLOUDSDK_COMPUTE_REGION=us-central1'
      - 'CLOUDSDK_CONTAINER_CLUSTER=embassy-appointments'

images:
  - 'us-docker.pkg.dev/$PROJECT_ID/embassy-appointments/app:$SHORT_SHA'
```

---

## Summary

This GCP architecture provides:

✅ **High Availability**: Multi-zone/multi-region, auto-scaling, health checks  
✅ **Security**: Cloud Armor WAF, private networking, Binary Authorization  
✅ **Scalability**: GKE Autopilot auto-scales from 3 to 10+ pods seamlessly  
✅ **Observability**: Cloud Monitoring, Logging, Trace, Profiler  
✅ **Cost-Effective**: ~$655-1,045/month with Autopilot (even lower with discounts)  
✅ **Compliance-Ready**: Security Command Center, audit logs, encryption  
✅ **Serverless Operations**: Autopilot eliminates node management  

### GCP vs Azure Comparison

| Feature | GCP | Azure |
|---------|-----|-------|
| **Kubernetes** | GKE Autopilot (serverless) | AKS (managed nodes) |
| **Container Registry** | Artifact Registry | ACR |
| **Secrets** | Secret Manager | Key Vault |
| **Database** | Cloud SQL | Azure Database |
| **Load Balancer** | Cloud Load Balancing | Application Gateway |
| **WAF** | Cloud Armor | Azure WAF |
| **Monitoring** | Cloud Monitoring | Azure Monitor |
| **Cost (est.)** | $655-1,045/mo | $900-1,200/mo |
| **Ease of Use** | Simpler (Autopilot) | More control |

Both platforms are excellent choices. GCP offers simpler operations with Autopilot, while Azure provides more fine-grained control and may be preferred for Microsoft-centric organizations.
