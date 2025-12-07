# Helm Chart Guide - Embassy Appointment System

This document explains the Helm chart structure and the purpose of each file in the deployment.

---

## Overview

The Helm chart packages all Kubernetes resources needed to deploy the Embassy Appointment System. It supports multiple environments (development, production) through values files.

**Chart Location**: `helm-chart/`

---

## Chart Structure

```
helm-chart/
├── Chart.yaml              # Chart metadata and version information
├── values.yaml             # Default configuration values
├── values-dev.yaml         # Development environment overrides
├── values-prod.yaml        # Production environment overrides
└── templates/              # Kubernetes resource templates
    ├── _helpers.tpl        # Template helper functions
    ├── configmap.yaml      # Non-sensitive configuration
    ├── deployment.yaml     # Application deployment specification
    ├── hpa.yaml            # Horizontal Pod Autoscaler
    ├── ingress.yaml        # HTTP routing rules
    ├── networkpolicy.yaml  # Network security policies
    ├── pdb.yaml            # Pod Disruption Budget
    ├── pvc.yaml            # Persistent Volume Claim for data
    ├── secret.yaml         # Sensitive configuration
    ├── service.yaml        # Service definition
    ├── serviceaccount.yaml # Kubernetes service account
    └── servicemonitor.yaml # Prometheus monitoring
```

---

## Core Files

### Chart.yaml
**Purpose**: Defines chart metadata, version, and dependencies.

**Key Fields**:
- `name`: Chart name (embassy-appointments)
- `version`: Chart version (1.0.0)
- `appVersion`: Application version (1.0.0)
- `description`: Human-readable chart description

**Usage**: Helm uses this for package management and version tracking.

---

### values.yaml
**Purpose**: Default configuration values for all environments.

**Key Sections**:
```yaml
replicaCount: 3              # Number of pod replicas
image:
  repository: embassy-appointments
  tag: "latest"
  pullPolicy: IfNotPresent
  
resources:                   # CPU/Memory limits
  limits:
    cpu: 500m
    memory: 512Mi
    
autoscaling:                 # HPA configuration
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  
ingress:                     # HTTP routing
  enabled: true
  className: "nginx"
  hosts:
    - host: appointments.example.com
```

**Usage**: Provides sensible defaults. Override with environment-specific values files.

---

### values-dev.yaml
**Purpose**: Development environment overrides.

**Key Differences from Production**:
```yaml
replicaCount: 1              # Single replica (not HA)
image:
  tag: "latest"
  pullPolicy: Never          # Use pre-loaded local images
  
resources:
  limits:
    cpu: 200m                # Lower resource limits
    memory: 128Mi
    
autoscaling:
  enabled: false             # No auto-scaling in dev
  
ingress:
  hosts:
    - host: appointments.local  # Local DNS
```

**Usage**: `helm install -f values-dev.yaml`

---

### values-prod.yaml
**Purpose**: Production environment configuration.

**Key Features**:
```yaml
replicaCount: 3              # High availability
image:
  pullPolicy: Always         # Always check for updates
  
resources:
  limits:
    cpu: 1000m               # Higher resources
    memory: 1Gi
    
autoscaling:
  enabled: true              # Scale 3-10 replicas
  
podDisruptionBudget:
  enabled: true              # Ensure availability during updates
  
networkPolicy:
  enabled: true              # Network segmentation
```

**Usage**: `helm install -f values-prod.yaml`

---

## Template Files

### _helpers.tpl
**Purpose**: Reusable template functions to avoid repetition.

**Functions**:
- `embassy-appointments.fullname`: Generates consistent resource names
- `embassy-appointments.labels`: Standard Kubernetes labels
- `embassy-appointments.selectorLabels`: Pod selector labels
- `embassy-appointments.serviceAccountName`: Service account name

**Example**:
```yaml
{{- define "embassy-appointments.fullname" -}}
{{- .Release.Name }}-embassy-appointments
{{- end }}
```

**Usage**: Called by other templates: `{{ include "embassy-appointments.fullname" . }}`

---

### deployment.yaml
**Purpose**: Defines the Deployment resource that manages application pods.

**Key Features**:
- **Replicas**: Number of pods to run
- **Rolling updates**: MaxSurge/MaxUnavailable configuration
- **Health probes**: Liveness, readiness, and startup checks
- **Resource limits**: CPU and memory constraints
- **Environment variables**: From ConfigMap and Secret
- **Volume mounts**: Persistent storage for SQLite database

**Template Logic**:
```yaml
replicas: {{ .Values.replicaCount }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

---

### service.yaml
**Purpose**: Creates a Service to expose pods within the cluster.

**Configuration**:
- **Type**: ClusterIP (internal only)
- **Port**: 80 (external) → 8080 (container)
- **Selector**: Routes to pods with matching labels

**Why ClusterIP**: Ingress controller handles external access; service is internal.

---

### ingress.yaml
**Purpose**: Defines HTTP routing rules to reach the application externally.

**Features**:
- **Host-based routing**: `appointments.local` or `appointments.example.com`
- **Path routing**: `/` routes to the service
- **TLS support**: Optional HTTPS configuration
- **Annotations**: NGINX-specific settings

**Example**:
```yaml
rules:
  - host: appointments.local
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: appointments-service
              port: 80
```

---

### configmap.yaml
**Purpose**: Stores non-sensitive configuration as environment variables.

**Contains**:
```yaml
data:
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  DATABASE_PATH: "/data/appointments.db"
  MAX_APPOINTMENTS_PER_DAY: "100"
```

**Usage**: Mounted as environment variables in pods.

---

### secret.yaml
**Purpose**: Stores sensitive configuration (encrypted in etcd).

**Contains**:
```yaml
data:
  SECRET_KEY: <base64-encoded>
  API_KEY: <base64-encoded>
```

**Security**: Values are base64-encoded (not encrypted in the manifest). Use external secret management (Vault, Sealed Secrets) for production.

---

### hpa.yaml
**Purpose**: Horizontal Pod Autoscaler for automatic scaling.

**Configuration**:
```yaml
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

**Behavior**: Scales pods up when CPU > 70%, down when CPU < 70%.

---

### pvc.yaml
**Purpose**: Persistent Volume Claim for SQLite database storage.

**Configuration**:
```yaml
accessModes:
  - ReadWriteOnce
resources:
  requests:
    storage: 1Gi
```

**Lifecycle**: Persists data across pod restarts and redeployments.

---

### pdb.yaml
**Purpose**: Pod Disruption Budget ensures minimum availability during voluntary disruptions (updates, node drains).

**Configuration**:
```yaml
minAvailable: 2  # Keep at least 2 pods running during updates
```

**Effect**: Prevents draining nodes if it would violate the budget.

---

### networkpolicy.yaml
**Purpose**: Network segmentation - controls pod-to-pod communication.

**Rules**:
```yaml
ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ingress-nginx  # Only ingress controller can reach pods
```

**Security**: Implements zero-trust networking.

---

### serviceaccount.yaml
**Purpose**: Creates a Kubernetes identity for pods to interact with the API.

**Usage**: Required for reading ConfigMaps, Secrets, or accessing cloud APIs.

**Configuration**:
```yaml
metadata:
  name: embassy-appointments
  annotations:
    # Cloud provider annotations (e.g., AWS IAM role)
```

---

### servicemonitor.yaml
**Purpose**: Prometheus ServiceMonitor for metrics collection.

**Configuration**:
```yaml
endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

**Requirement**: Prometheus Operator must be installed in the cluster.

---

## Deployment Commands

### Install
```powershell
# Development
helm install appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments --create-namespace

# Production
helm install appointments ./helm-chart -f helm-chart/values-prod.yaml -n embassy-appointments --create-namespace
```

### Upgrade
```powershell
# Update existing deployment
helm upgrade appointments ./helm-chart -f helm-chart/values-dev.yaml -n embassy-appointments
```

### Uninstall
```powershell
helm uninstall appointments -n embassy-appointments
```

### Debug
```powershell
# Dry-run to see generated YAML
helm install appointments ./helm-chart -f helm-chart/values-dev.yaml --dry-run --debug

# Template without installing
helm template appointments ./helm-chart -f helm-chart/values-dev.yaml
```

---

## Customization

### Adding New Configuration
1. Add to `values.yaml` with default value
2. Reference in templates: `{{ .Values.newConfig }}`
3. Override in environment files if needed

### Adding New Resources
1. Create template in `templates/` directory
2. Use helpers from `_helpers.tpl`
3. Add conditional rendering: `{{- if .Values.feature.enabled }}`

---

## Best Practices

1. **Never commit secrets**: Use external secret management
2. **Version everything**: Update Chart.yaml version on changes
3. **Test with dry-run**: Always test before applying
4. **Use helpers**: DRY principle with `_helpers.tpl`
5. **Document changes**: Update this guide when adding features

---

## Troubleshooting

### Chart fails to install
```powershell
# Check syntax
helm lint ./helm-chart

# Validate against cluster
helm install --dry-run --debug appointments ./helm-chart
```

### Values not applied
```powershell
# Verify merged values
helm get values appointments -n embassy-appointments --all
```

### Resources not created
```powershell
# Check template output
helm get manifest appointments -n embassy-appointments
```

---

**Last Updated**: December 5, 2025  
**Chart Version**: 1.0.0
