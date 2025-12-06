# Architectural Considerations & Solutions

## Overview
Addressing the three key considerations for production deployment.

---

## 1. Application Access: How would someone access your application?

### Local Development (KIND)

#### Option A: Port Forwarding
```bash
kubectl port-forward svc/appointment-service 8080:80 -n embassy-appointments
```
- **Access**: http://localhost:8080
- **Pros**: Simple, secure, no additional setup
- **Cons**: Terminal must stay open, single user
- **Use Case**: Development, debugging

#### Option B: NodePort Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: appointment-service
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
```
- **Access**: http://localhost:30080 (or node IP)
- **Pros**: Stable port, multiple connections
- **Cons**: Limited port range (30000-32767)
- **Use Case**: Local testing with KIND

#### Option C: Ingress with Local DNS
```bash
# With ingress-nginx in KIND
# Add to /etc/hosts: 127.0.0.1 appointments.local
```
- **Access**: http://appointments.local
- **Pros**: Production-like setup, hostname-based routing
- **Cons**: Requires ingress controller, DNS setup
- **Use Case**: Testing production configuration locally

---

### Cloud Deployment (Azure/GCP)

#### Option A: Load Balancer Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: appointment-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
```
- **Access**: Public IP provided by cloud
- **Pros**: Simple, automatic provisioning
- **Cons**: Costs money, public by default
- **Use Case**: Simple public applications

#### Option B: Ingress with TLS (Recommended)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - appointments.embassy.com
    secretName: app-tls-cert
  rules:
  - host: appointments.embassy.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: appointment-service
            port:
              number: 80
```
- **Access**: https://appointments.embassy.com
- **Pros**: TLS/SSL, hostname routing, cost-effective
- **Cons**: Requires DNS, cert-manager setup
- **Use Case**: Production applications

#### Option C: API Gateway
- **Azure**: Azure Application Gateway, API Management
- **GCP**: Cloud Load Balancing, Apigee
- **Pros**: Advanced features (rate limiting, auth, monitoring)
- **Cons**: Additional cost and complexity
- **Use Case**: Enterprise applications

---

### Security & Access Control

#### Authentication Options:
1. **No Auth** (Demo/Internal)
2. **Basic Auth** (Simple, Ingress annotation)
3. **OAuth2/OIDC** (Microsoft Entra ID, Google Identity)
4. **mTLS** (Service mesh)

#### Network Security:
1. **Public Internet** (with WAF)
2. **VPN/Private Network** (Azure Private Link, GCP Private Service Connect)
3. **IP Whitelisting** (Ingress/LB annotations)

**Decision Needed**: Access pattern for demo vs production?

---

## 2. Application Updates: How do you handle application updates?

### Deployment Strategy

#### Option A: Rolling Update (Recommended)
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # 1 extra pod during update
      maxUnavailable: 0    # No downtime
  replicas: 3
```

**Process**:
1. New version pod created
2. Wait for readiness probe
3. Old pod terminated
4. Repeat until all updated

**Pros**:
- Zero downtime
- Automatic rollback if health checks fail
- Resource efficient

**Cons**:
- Brief period with mixed versions
- Slower than recreate

---

#### Option B: Blue/Green Deployment
```yaml
# Two complete deployments: blue (current), green (new)
# Switch traffic via Service selector change
```

**Process**:
1. Deploy new version (green) alongside old (blue)
2. Test green thoroughly
3. Switch service selector to green
4. Keep blue running briefly for quick rollback

**Pros**:
- Instant switch
- Easy rollback (switch back)
- No version mixing

**Cons**:
- 2x resources during deployment
- More complex automation

---

#### Option C: Canary Deployment
```yaml
# Use service mesh or weighted routing
# Gradually shift traffic: 10% → 50% → 100%
```

**Process**:
1. Deploy new version with 10% traffic
2. Monitor metrics
3. Gradually increase traffic
4. Rollout fully or rollback

**Pros**:
- Risk mitigation
- Real-world testing
- Data-driven decisions

**Cons**:
- Requires service mesh (Istio, Linkerd) or advanced ingress
- Complex monitoring needed

---

### CI/CD Pipeline

#### GitOps Approach (Recommended)
```
Code Change → Git Push → CI Build → Update Helm Values → ArgoCD/Flux → K8s Deploy
```

**Tools**:
- **Git**: Source of truth
- **GitHub Actions/GitLab CI/Azure DevOps**: Build & test
- **ArgoCD/Flux**: Continuous deployment
- **Helm**: Package management

**Example Workflow**:
```yaml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    
    - name: Build Docker image
      run: docker build -t app:${{ github.sha }} .
    
    - name: Push to registry
      run: docker push app:${{ github.sha }}
    
    - name: Update Helm values
      run: |
        sed -i 's/tag: .*/tag: ${{ github.sha }}/' values.yaml
        git commit -am "Update image tag"
        git push
    
    - name: ArgoCD sync (or Flux auto-detects)
      run: argocd app sync appointment-app
```

---

#### Traditional CI/CD
```
Code Change → CI → Build → Test → Push Image → Deploy to K8s
```

**Tools**:
- Jenkins
- GitHub Actions
- Azure DevOps
- GitLab CI

---

### Update Best Practices

1. **Version Everything**
   - Docker images: Use git SHA or semantic versioning
   - Helm charts: Chart version in Chart.yaml
   - Application: VERSION env var

2. **Automated Testing**
   - Unit tests in CI
   - Integration tests before deploy
   - Smoke tests after deploy

3. **Gradual Rollout**
   - Deploy to dev → staging → production
   - Use namespaces or separate clusters

4. **Monitoring**
   - Watch error rates during deploy
   - Set up alerts for anomalies
   - Auto-rollback on threshold breach

5. **Database Migrations**
   - Run as init container or separate job
   - Make backwards compatible
   - Test rollback scenarios

---

### Rollback Strategy

#### Automatic Rollback
```yaml
# If readiness probe fails, new pods never become ready
# Rolling update stops automatically
```

#### Manual Rollback
```bash
# Helm rollback
helm rollback appointment-app 1

# Kubernetes rollback
kubectl rollout undo deployment/appointment-app -n embassy-appointments

# Check rollout status
kubectl rollout status deployment/appointment-app -n embassy-appointments
```

#### Version Pinning
```yaml
# Keep last 5 revisions
spec:
  revisionHistoryLimit: 5
```

**Decision Needed**: CI/CD tool preference? GitOps or traditional?

---

## 3. Configuration Management: Sensitive vs Non-Sensitive

### Configuration Types

#### Non-Sensitive Configuration → ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: embassy-appointments
data:
  # Application settings
  APP_NAME: "embassy-appointment-system"
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  
  # Business logic
  EMBASSY_NAME: "US Embassy"
  AVAILABLE_SLOTS_PER_DAY: "20"
  APPOINTMENT_DURATION_MINUTES: "30"
  MEDICAL_EXAM_VALIDITY_DAYS: "180"
  
  # Feature flags
  MEDICAL_EXAM_REQUIRED: "true"
  EMAIL_NOTIFICATIONS: "true"
  
  # Performance
  WORKERS: "4"
  TIMEOUT: "30"
```

**Usage in Pod**:
```yaml
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config
    # Or individual keys:
    env:
    - name: APP_NAME
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_NAME
```

---

#### Sensitive Configuration → Secret

**Option A: Kubernetes Secrets (Base64)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: embassy-appointments
type: Opaque
data:
  SECRET_KEY: <base64-encoded-value>
  DATABASE_PASSWORD: <base64-encoded-value>
  API_KEY: <base64-encoded-value>
```

**Pros**: Native, simple
**Cons**: Base64 is not encryption, stored in etcd

---

**Option B: Sealed Secrets**
```yaml
# Encrypted in git, only cluster can decrypt
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: app-secrets
spec:
  encryptedData:
    SECRET_KEY: AgBi8... (encrypted)
```

**Pros**: Safe to commit to git, GitOps friendly
**Cons**: Requires Sealed Secrets controller
**Tool**: kubeseal CLI

---

**Option C: External Secrets Operator**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault  # or aws-secrets-manager, gcp-secret-manager
    kind: SecretStore
  target:
    name: app-secrets
  data:
  - secretKey: SECRET_KEY
    remoteRef:
      key: app-secret-key
```

**Pros**: 
- Secrets stay in vault (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager)
- Centralized management
- Audit logs
- Rotation support

**Cons**: Additional dependency, complexity

---

**Option D: HashiCorp Vault**
```yaml
# Agent injector or CSI driver
# Secrets injected at runtime
```

**Pros**: 
- Dynamic secrets
- Encryption as a service
- Advanced policies

**Cons**: 
- Complex setup
- Additional infrastructure

---

### Secret Management Strategy

#### For Different Environments:

**Local Development (KIND)**:
- Plain Kubernetes Secrets (acceptable for demo)
- Or Sealed Secrets (if practicing GitOps)

**Cloud Production (Azure/GCP)**:
- **Azure**: External Secrets Operator + Azure Key Vault
- **GCP**: External Secrets Operator + Secret Manager
- Alternative: Workload Identity + direct API calls

---

### Configuration Best Practices

#### 1. Separation of Concerns
```
ConfigMap: Application behavior settings
Secret: Credentials, API keys, certificates
```

#### 2. Environment-Specific Values
```
helm-chart/
├── values.yaml          # Defaults
├── values-dev.yaml      # Development overrides
├── values-staging.yaml  # Staging overrides
└── values-prod.yaml     # Production overrides
```

```bash
# Deploy to different environments
helm install app ./helm-chart -f values-dev.yaml -n dev
helm install app ./helm-chart -f values-prod.yaml -n production
```

#### 3. Immutable Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v1  # Version in name
immutable: true         # Cannot be modified
```

**Why**: 
- Forces deployment to pick up changes
- Prevents accidental modifications
- Clear version history

#### 4. Secret Rotation
- Automate rotation (External Secrets)
- Grace period for updates
- Monitor for expiration

#### 5. RBAC for Secrets
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: embassy-appointments
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-secrets"]  # Specific secret only
  verbs: ["get"]
```

---

### Sensitive Data Examples

**Should be in Secrets**:
- Database passwords
- API keys (payment, email services)
- Secret keys (JWT signing, encryption)
- TLS certificates private keys
- OAuth client secrets
- SSH keys

**Can be in ConfigMaps**:
- Database host/port
- API endpoints (URLs)
- Feature flags
- Timeout values
- Cache configuration
- Public configuration

---

### Configuration Injection Methods

#### 1. Environment Variables (Recommended)
```yaml
envFrom:
- configMapRef:
    name: app-config
- secretRef:
    name: app-secrets
```

#### 2. Mounted Files
```yaml
volumes:
- name: config
  configMap:
    name: app-config
- name: secrets
  secret:
    secretName: app-secrets
volumeMounts:
- name: config
  mountPath: /etc/config
- name: secrets
  mountPath: /etc/secrets
  readOnly: true
```

**Use for**: Configuration files (JSON, YAML), certificates

---

## Decision Needed From You:

1. **Access Method**: 
   - Local: Port-forward, NodePort, or Ingress?
   - Production: LoadBalancer or Ingress with TLS?

2. **Update Strategy**: Rolling Update, Blue/Green, or Canary?

3. **CI/CD**: GitHub Actions, Azure DevOps, or GitLab CI?

4. **GitOps**: Use ArgoCD/Flux or traditional deployment?

5. **Secret Management**: 
   - Local: Plain Secrets or Sealed Secrets?
   - Production: External Secrets with Key Vault or plain Secrets?

6. **Monitoring**: Include Prometheus/Grafana setup?

---

## My Recommendations:

### Local (KIND):
- **Access**: Ingress with local DNS (production-like)
- **Updates**: Rolling update with Helm
- **Secrets**: Plain K8s secrets (demo acceptable)
- **CI/CD**: GitHub Actions for image building

### Production (Azure/GCP):
- **Access**: Ingress with TLS (cert-manager + Let's Encrypt)
- **Updates**: Rolling update with HPA, PDB
- **Secrets**: External Secrets Operator + Cloud Key Vault
- **CI/CD**: GitHub Actions + ArgoCD (GitOps)
- **Monitoring**: Prometheus + Grafana

### Update Process:
1. Developer pushes code to GitHub
2. GitHub Actions runs tests, builds image
3. Updates Helm values with new image tag
4. ArgoCD detects change, deploys with rolling update
5. Health checks ensure success
6. Automatic rollback on failure

This provides:
- Production-grade deployment
- Zero-downtime updates
- Secure secret management
- GitOps benefits (audit trail, easy rollback)
- Works identically in KIND, Azure, and GCP
