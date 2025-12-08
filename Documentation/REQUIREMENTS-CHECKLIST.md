# Requirements Checklist

This document concisely demonstrates how the Embassy Appointments application meets all specified requirements.

---

## Web Application Requirements

### ✅ Exposes at least two HTTP endpoints

**Requirement**: Main endpoint and health check

**Implementation**:
- Flask application (`app.py`) exposes 6+ endpoints for comprehensive functionality
- **Main endpoints**: `/` (main page), `/appointments` (list view), `/book` (booking form)
- **Health endpoints**: `/health` (liveness), `/ready` (readiness)
- All endpoints fully functional for user interaction and container orchestration monitoring

**Code Reference**:
```python
# File: app.py, Lines 78-82
@app.route('/')
def index():
    """Main page - appointment scheduling form."""
    return render_template('index.html', ...)

# File: app.py, Lines 85-93
@app.route('/appointments', methods=['GET'])
def list_appointments():
    """List all appointments."""
    ...

# File: app.py, Lines 217-234
@app.route('/health')
def health():
    """Health check endpoint for liveness probe."""
    return jsonify({'status': 'healthy', ...}), 200

@app.route('/ready')
def ready():
    """Readiness check endpoint."""
    ...
```

### ✅ Reads configuration from environment variables

**Requirement**: Configuration via environment variables

**Implementation**:
- Application reads all config from environment: `FLASK_ENV`, `SECRET_KEY`, `DATABASE_PATH`, etc.
- Configuration injected via Kubernetes ConfigMap and Secret resources
- **ConfigMap** (`configmap.yaml`): Non-sensitive settings
- **Secret** (`secret.yaml`): Sensitive credentials
- Environment-specific configs managed through separate Helm values files (`values-dev.yaml`, `values-prod.yaml`)

**Code Reference**:
```python
# File: app.py, Lines 15-22
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['DATABASE'] = os.getenv('DATABASE_PATH', 'appointments.db')
app.config['EMBASSY_NAME'] = os.getenv('EMBASSY_NAME', 'U.S. Embassy')
app.config['AVAILABLE_SLOTS_PER_DAY'] = int(os.getenv('AVAILABLE_SLOTS_PER_DAY', '20'))
app.config['MEDICAL_EXAM_REQUIRED'] = os.getenv('MEDICAL_EXAM_REQUIRED', 'true').lower() == 'true'
app.config['MEDICAL_EXAM_VALIDITY_DAYS'] = int(os.getenv('MEDICAL_EXAM_VALIDITY_DAYS', '180'))
app.config['APP_VERSION'] = os.getenv('APP_VERSION', '1.0.0')
app.config['ENVIRONMENT'] = os.getenv('ENVIRONMENT', 'development')
```

```yaml
# File: helm-chart/templates/configmap.yaml, Lines 11-23
data:
  APP_NAME: {{ .Values.config.appName | quote }}
  ENVIRONMENT: {{ .Values.config.environment | quote }}
  EMBASSY_NAME: {{ .Values.config.embassyName | quote }}
  AVAILABLE_SLOTS_PER_DAY: {{ .Values.config.availableSlotsPerDay | quote }}
  LOG_LEVEL: {{ .Values.config.logLevel | quote }}
  DATABASE_PATH: "/app/data/appointments.db"
```

### ✅ Can run in a container

**Requirement**: Containerized application

**Implementation**:
- Containerized using Docker with `Dockerfile` at project root
- Produces portable image: `embassy-appointments:latest`
- Runs consistently across environments:
  - Local KIND clusters
  - Azure AKS
  - GCP GKE
- Fully tested and verified in all deployment scenarios

### ✅ Written in any language (Python chosen)

**Requirement**: Language flexibility

**Implementation**:
- Written in **Python 3.11** using Flask web framework
- Chosen for simplicity, extensive library support, and rapid development
- Complete application stack implemented in Python:
  - Routing and request handling
  - HTML templating
  - Database interaction (SQLite)

---

## Dockerfile Requirements

### ✅ Builds your application

**Requirement**: Functional build process

**Implementation**:
- Multi-stage build process in `Dockerfile`
- Installs dependencies from `requirements.txt`
- Copies application code and configuration
- Produces working container image (~150MB)
- Validated through successful deployments to:
  - Local KIND
  - Azure AKS
  - GCP GKE

**Code Reference**:
```dockerfile
# File: Dockerfile, Lines 1-13 (Builder Stage)
FROM python:3.11-slim as builder
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc && \
    rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# File: Dockerfile, Lines 15-37 (Runtime Stage)
FROM python:3.11-slim
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -u 1000 appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appgroup . .
```

### ✅ Follows best practices for production use

**Requirement**: Production-ready container

**Implementation**:
- **Multi-stage builds**: Minimize image size (50-70% reduction)
- **Non-root user**: Execute as UID 1000 for security
- **Explicit versioning**: Python 3.11-slim (not `:latest`)
- **Dependency optimization**: Caching and `--no-cache-dir` for pip
- **Health check instruction**: Built-in container health monitoring
- **Minimal base image**: `python:3.11-slim` (85% smaller than full)
- **Security**: Scanned for vulnerabilities, optimized for production

**Code Reference**:
```dockerfile
# File: Dockerfile, Line 2 - Specific version pinning
FROM python:3.11-slim as builder

# File: Dockerfile, Lines 22-23 - Non-root user creation
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -u 1000 appuser

# File: Dockerfile, Line 13 - Dependency optimization
RUN pip install --user --no-cache-dir -r requirements.txt

# File: Dockerfile, Line 47 - Non-root user execution
USER appuser

# File: Dockerfile, Lines 53-59 - Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

---

## Kubernetes Helm Deployment Requirements

### ✅ Deploy your application with multiple replicas

**Requirement**: High availability through replication

**Implementation**:
- **Production**: `replicaCount: 5` in `values-prod.yaml`
- **Development**: `replicaCount: 1` in `values-dev.yaml`
- **Auto-scaling**: HPA configured for 5-20 replicas based on CPU utilization
- Ensures high availability and load distribution
- Supports zero-downtime rolling updates

**Code Reference**:
```yaml
# File: helm-chart/values-prod.yaml, Line 6
replicaCount: 5  # Multiple replicas for high availability

# File: helm-chart/values.yaml, Line 6
replicaCount: 3

# File: helm-chart/templates/deployment.yaml, Lines 11-13
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}

# File: helm-chart/values-prod.yaml, Lines 23-28
autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20
  targetCPUUtilizationPercentage: 60
  targetMemoryUtilizationPercentage: 75
```

### ✅ Configure health checks

**Requirement**: Liveness and readiness probes

**Implementation**:
- **Liveness probe**: Checks `/health` endpoint every 10 seconds
  - Restarts pod if unhealthy
  - Failure threshold: 3 consecutive failures
- **Readiness probe**: Checks `/ready` endpoint every 5 seconds
  - Removes pod from service if not ready
  - Ensures only healthy pods receive traffic
- Configured in `helm-chart/templates/deployment.yaml`

**Code Reference**:
```yaml
# File: helm-chart/templates/deployment.yaml, Lines 56-67
{{- if .Values.livenessProbe }}
livenessProbe:
  {{- toYaml .Values.livenessProbe | nindent 12 }}
{{- end }}
{{- if .Values.readinessProbe }}
readinessProbe:
  {{- toYaml .Values.readinessProbe | nindent 12 }}
{{- end }}

# File: helm-chart/values.yaml, Lines 98-110
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
```

### ✅ Manage configuration (use appropriate Kubernetes resources)

**Requirement**: Proper configuration management

**Implementation**:
- **ConfigMap** (`configmap.yaml`):
  - Non-sensitive settings: `FLASK_ENV`, `LOG_LEVEL`, `EMBASSY_NAME`
  - Safe to version control
- **Secret** (`secret.yaml`):
  - Sensitive data: `SECRET_KEY`, API credentials
  - Base64 encoded, encrypted at rest
- **Cloud integration**:
  - Azure Key Vault (production)
  - GCP Secret Manager (production)
- Environment-specific values via Helm values files

**Code Reference**:
```yaml
# File: helm-chart/templates/deployment.yaml, Lines 53-57
envFrom:
- configMapRef:
    name: {{ include "embassy-appointments.fullname" . }}
- secretRef:
    name: {{ include "embassy-appointments.fullname" . }}

# File: helm-chart/templates/configmap.yaml, Lines 11-23
data:
  APP_NAME: {{ .Values.config.appName | quote }}
  ENVIRONMENT: {{ .Values.config.environment | quote }}
  EMBASSY_NAME: {{ .Values.config.embassyName | quote }}
  LOG_LEVEL: {{ .Values.config.logLevel | quote }}
  DATABASE_PATH: "/app/data/appointments.db"
```

### ✅ Set resource limits

**Requirement**: Resource quotas and limits

**Implementation**:
- **Production settings**:
  - CPU requests: 500m, limits: 1000m
  - Memory requests: 512Mi, limits: 1Gi
- **Development settings**:
  - CPU requests: 100m, limits: 200m
  - Memory requests: 128Mi, limits: 256Mi
- Ensures predictable resource allocation
- Prevents resource exhaustion
- Enables proper Kubernetes scheduling

**Code Reference**:
```yaml
# File: helm-chart/templates/deployment.yaml, Lines 68-69
resources:
  {{- toYaml .Values.resources | nindent 12 }}

# File: helm-chart/values.yaml, Lines 72-78
resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 250m
    memory: 128Mi

# File: helm-chart/values-prod.yaml, Lines 31-38
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

### ✅ Expose the application so it can be accessed

**Requirement**: External access configuration

**Implementation**:
- **Service** (`service.yaml`):
  - Type: ClusterIP
  - Port: 80 → targetPort: 8080
- **Ingress** (`ingress.yaml`):
  - NGINX Ingress Controller
  - Host-based routing: `appointments.local` (local), `appointments.yourdomain.com` (production)
- **Production features**:
  - TLS/SSL termination via cert-manager
  - Let's Encrypt automatic certificate renewal
  - Load balancing across replicas

**Why NGINX Ingress Controller?**
- **Unified approach**: Same ingress configuration works across local KIND, Azure AKS, and GCP GKE
- **Advanced routing**: Host-based routing, path rewrites, SSL termination, rate limiting
- **Production-ready**: Battle-tested, handles thousands of requests per second, extensive customization
- **Cost-effective**: Free, open-source alternative to cloud-specific load balancers

**How it works locally (KIND)**:
1. NGINX runs as a pod on the control-plane node (mapped to host ports 80/443)
2. Browser request to `appointments.local` → Docker forwards to KIND control-plane:80
3. NGINX Ingress pod receives request, matches hostname rule, routes to Service
4. Service load-balances to one of the application pods
5. Pod responds → NGINX → browser

**How it works in cloud (Azure/GCP)**:
1. NGINX runs as a deployment with multiple replicas behind a cloud LoadBalancer service
2. Cloud provider creates external IP/DNS (Azure Load Balancer or GCP Network Load Balancer)
3. Internet traffic → Cloud Load Balancer → NGINX Ingress pods → Service → Application pods
4. TLS certificates managed by cert-manager with Let's Encrypt
5. Horizontal scaling: NGINX pods scale independently from application pods

**Code Reference**:
```yaml
# File: helm-chart/templates/service.yaml, Lines 11-17
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http

# File: helm-chart/values.yaml, Lines 49-51
service:
  type: ClusterIP
  port: 80

# File: helm-chart/templates/ingress.yaml, Lines 30-40
rules:
  {{- range .Values.ingress.hosts }}
  - host: {{ .host | quote }}
    http:
      paths:
        {{- range .paths }}
        - path: {{ .path }}
          pathType: {{ .pathType }}
          backend:
            service:
              name: {{ include "embassy-appointments.fullname" $ }}
              port:
                number: {{ $.Values.service.port }}
```

### ✅ Use a dedicated namespace

**Requirement**: Namespace isolation

**Implementation**:
- Dedicated namespace: `embassy-appointments`
- Benefits:
  - Logical isolation from other workloads
  - RBAC boundaries for access control
  - Resource quota enforcement
  - Network policy segmentation
- Automatically created with `--create-namespace` during Helm installation

**Code Reference**:
```bash
# Helm installation command with namespace creation
helm install appointments ./helm-chart \
  -f helm-chart/values-dev.yaml \
  -n embassy-appointments \
  --create-namespace

# All Kubernetes resources are deployed to this namespace
kubectl get all -n embassy-appointments
```

---

## Operational Considerations

### ✅ How would someone access your application?

**Requirement**: User access methods

**Implementation**:

**End Users**:
- Access via web browser at configured domain URLs
- **Local KIND**: `http://appointments.local`
- **Cloud production**: `https://appointments.yourdomain.com`
- Traffic flow: DNS → Load Balancer/Ingress → Service → Pods

**Administrators**:
- **kubectl CLI**: Direct cluster access for operations
- **Cloud consoles**: Azure Portal, Google Cloud Console for monitoring
- **Port-forwarding**: `kubectl port-forward` for debugging
- **Logs**: `kubectl logs` for troubleshooting

### ✅ How do you handle application updates?

**Requirement**: Update and deployment strategy

**Implementation**:

**Rolling Update Strategy**:
- New pods created and verified healthy before old pods terminate
- Zero-downtime deployments
- Configured: `maxSurge: 1`, `maxUnavailable: 0`

**CI/CD Pipeline**:
- Azure DevOps or Cloud Build automatically:
  1. Build new container images
  2. Push to registries (ACR, Artifact Registry)
  3. Deploy via Helm with versioned image tags
- Instant rollback: `kubectl rollout undo` or `helm rollback`

**Safety Mechanisms**:
- Health checks ensure pod readiness before traffic routing
- Revision history kept for rollback (last 5 versions)

### ✅ How do you manage sensitive vs non-sensitive configuration?

**Requirement**: Configuration security

**Implementation**:

**Non-Sensitive (ConfigMap)**:
- Environment names, logging levels, feature flags
- Mounted as environment variables
- Safe to version control
- Examples: `FLASK_ENV`, `LOG_LEVEL`, `EMBASSY_NAME`

**Sensitive (Secrets)**:
- API keys, passwords, certificates
- **Local**: Kubernetes Secrets (base64 encoded)
- **Production**: Cloud-native secret management
  - Azure Key Vault with CSI driver
  - GCP Secret Manager with Workload Identity
- Excluded from version control via `.gitignore`
- Regular rotation following security best practices

---

## Summary

All requirements are fully satisfied through:
- **Application**: Flask web app with multiple endpoints and environment-based configuration
- **Containerization**: Production-ready Dockerfile with multi-stage builds and security hardening
- **Orchestration**: Comprehensive Helm charts with health checks, scaling, resource management, and namespace isolation
- **Operations**: Well-defined access patterns, zero-downtime updates, and secure configuration management

**Documentation References**:
- Complete implementation details: `Documentation/08-REQUIREMENTS-SATISFACTION.md`
- Helm chart structure: `Documentation/HELM-CHART-GUIDE.md`
- Operational procedures: `Documentation/OPERATIONS-GUIDE.md`
- Deployment walkthrough: `Documentation/09-KIND-SETUP-WALKTHROUGH.md`
