# Kubernetes Manifests Requirements

## Objective
Deploy the appointment scheduling application to Kubernetes with production-ready configurations using Helm.

---

## Required Kubernetes Resources

### 1. Deployment with Multiple Replicas

#### Replica Count Options:
- **Development**: 1-2 replicas
- **Production**: 3-5 replicas (HA)
- **High Traffic**: 5+ with HPA

**Why Multiple Replicas**:
- High availability
- Zero-downtime deployments
- Load distribution
- Fault tolerance

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

---

### 2. Health Checks

#### A. Liveness Probe
**Purpose**: Restart container if application is deadlocked
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
```

#### B. Readiness Probe
**Purpose**: Remove from service if not ready to handle traffic
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3
```

#### C. Startup Probe (Optional)
**Purpose**: Allow slow-starting apps extra time
```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 30
```

**Decision Needed**: Which probes? (Recommend: All three for production)

---

### 3. Resource Limits

#### Why Resource Limits Matter:
- Prevent resource starvation
- Enable proper scheduling
- Cost optimization
- Predictable performance

#### Sizing Options:

**Option A: Minimal (Development)**
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

**Option B: Standard (Recommended)**
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "250m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

**Option C: High Performance**
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "500m"
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

**Decision Needed**: Which tier? (Recommend: Standard for demo)

---

### 4. Configuration Management

#### A. ConfigMap
**Purpose**: Non-sensitive configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_NAME: "embassy-appointment-system"
  EMBASSY_NAME: "US Embassy"
  AVAILABLE_SLOTS_PER_DAY: "20"
  MEDICAL_EXAM_REQUIRED: "true"
```

#### B. Secret
**Purpose**: Sensitive data (encrypted at rest)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  SECRET_KEY: <base64-encoded>
  DATABASE_PASSWORD: <base64-encoded>
```

**Decision Needed**: Use external secret management? (Sealed Secrets, External Secrets Operator, Vault?)

---

### 5. Service Exposure

#### Option A: ClusterIP (Default)
```yaml
type: ClusterIP
```
- Internal only
- Use with Ingress

#### Option B: NodePort
```yaml
type: NodePort
nodePort: 30080
```
- Direct node access
- Good for KIND local testing

#### Option C: LoadBalancer
```yaml
type: LoadBalancer
```
- Cloud provider LB
- Production use

**Recommendation**: 
- **Local (KIND)**: NodePort or Ingress
- **Cloud**: LoadBalancer or Ingress

---

### 6. Dedicated Namespace

**Why Namespaces**:
- Isolation
- Resource quotas
- RBAC boundaries
- Multi-tenancy

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: embassy-appointments
  labels:
    app: appointment-system
    environment: production
```

**Resource Quotas** (Optional):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: app-quota
  namespace: embassy-appointments
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
```

---

## Helm Chart Structure

### Option A: Simple Helm Chart
```
helm-chart/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── ingress.yaml (optional)
│   └── _helpers.tpl
```

### Option B: Advanced with Sub-Charts
```
helm-chart/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── networkpolicy.yaml
│   └── _helpers.tpl
├── charts/
│   └── postgresql/ (if using)
```

**Decision Needed**: Simple or Advanced? (Recommend: Simple for this project)

---

## Additional Kubernetes Features

### 1. Horizontal Pod Autoscaler (HPA)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: appointment-app
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Include?** Yes for production, optional for demo.

---

### 2. Pod Disruption Budget (PDB)
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: appointment-app
```

**Purpose**: Ensure availability during voluntary disruptions (node drains, upgrades).

**Include?** Recommended for production.

---

### 3. Network Policy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-network-policy
spec:
  podSelector:
    matchLabels:
      app: appointment-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

**Purpose**: Network segmentation, security.

**Include?** Optional, depends on security requirements.

---

### 4. Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - appointments.example.com
    secretName: app-tls
  rules:
  - host: appointments.example.com
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

**Include?** Yes for production, optional for local KIND.

---

## Helm vs Kustomize

### Helm
**Pros**:
- Templating engine
- Package manager
- Version control
- Easy upgrades/rollbacks
- Values override

**Cons**:
- Learning curve
- Template complexity

### Kustomize
**Pros**:
- Native to kubectl
- Overlay approach
- Simpler for basic use

**Cons**:
- Less flexible
- No package management

**Recommendation**: Helm (requested in requirements)

---

## Deployment Strategies

### 1. Rolling Update (Default)
- Zero downtime
- Gradual rollout
- Easy rollback

### 2. Blue/Green
- Instant switch
- Full rollback capability
- Double resources temporarily

### 3. Canary
- Progressive traffic shift
- Risk mitigation
- Requires service mesh or ingress controller

**Recommendation**: Rolling Update for this project.

---

## Decision Needed From You:

1. **Resource Tier**: Minimal, Standard, or High Performance?
2. **Replicas**: 2, 3, or 5 for production?
3. **Include HPA**: Yes or No?
4. **Include PDB**: Yes or No?
5. **Secret Management**: Plain Secrets, Sealed Secrets, or External Secrets?
6. **Ingress**: Include for production? Ingress controller preference (nginx, traefik)?
7. **Monitoring**: Include ServiceMonitor for Prometheus?

---

## My Recommendation:
- **Resources**: Standard tier (128Mi/250m request, 256Mi/500m limit)
- **Replicas**: 3 (good HA without over-provisioning)
- **Health Probes**: All three (liveness, readiness, startup)
- **HPA**: Yes, scale 3-10 pods at 70% CPU
- **PDB**: Yes, minAvailable: 2
- **Secrets**: Plain K8s secrets (can upgrade later)
- **Ingress**: Yes with nginx-ingress
- **Namespace**: Dedicated `embassy-appointments`

This configuration provides:
- High availability
- Auto-scaling
- Proper resource management
- Production-ready security
- Easy local testing with KIND
