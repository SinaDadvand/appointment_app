# Dockerfile Requirements & Best Practices

## Objective
Create an optimized, secure, production-ready Dockerfile for the appointment scheduling application.

---

## Best Practices to Implement

### 1. Multi-Stage Build
**Why**: Reduces final image size by separating build dependencies from runtime dependencies.

```dockerfile
# Stage 1: Build stage
FROM python:3.11-slim as builder
# Install build dependencies, compile, etc.

# Stage 2: Runtime stage
FROM python:3.11-slim
# Copy only necessary artifacts
```

**Benefits**:
- Smaller image size (50-70% reduction typical)
- Faster deployments
- Reduced attack surface

---

### 2. Base Image Selection

#### Option A: python:3.11-slim (Recommended)
- Size: ~120MB base
- Contains essentials only
- Official Python image

#### Option B: python:3.11-alpine
- Size: ~50MB base
- Even smaller
- May have compatibility issues with some packages

#### Option C: python:3.11
- Size: ~900MB base
- Full Debian image
- Not recommended for production

**Recommendation**: `python:3.11-slim` for balance of size and compatibility.

---

### 3. Security Best Practices

#### A. Non-Root User
```dockerfile
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser
USER appuser
```
**Why**: Prevents privilege escalation attacks.

#### B. Minimize Layers
- Combine RUN commands with `&&`
- Clean up in same layer
```dockerfile
RUN apt-get update && apt-get install -y package \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

#### C. Use Specific Versions
```dockerfile
FROM python:3.11.6-slim  # Not just :latest
```
**Why**: Reproducible builds, no surprises.

#### D. Scan for Vulnerabilities
- Use minimal base images
- Keep dependencies updated
- Regular security scans

---

### 4. Optimization Strategies

#### A. Layer Caching
```dockerfile
# Copy requirements first (changes less frequently)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code (changes more frequently)
COPY . .
```

#### B. .dockerignore File
```
__pycache__
*.pyc
*.pyo
*.pyd
.git
.gitignore
.vscode
.idea
*.md
tests/
.env
venv/
*.sqlite
```
**Why**: Smaller context, faster builds, no sensitive data.

#### C. Minimize Installed Packages
- Install only runtime dependencies
- Use `--no-cache-dir` with pip
- Remove build tools after use

---

### 5. Production Optimizations

#### A. Use Production WSGI Server
```dockerfile
# NOT for production: python app.py
# USE: gunicorn or uwsgi
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "app:app"]
```

**Options**:
- **Gunicorn**: Popular, Python-based, easy to configure
- **uWSGI**: More features, slightly more complex
- **Uvicorn**: For async apps (FastAPI)

#### B. Health Check
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

#### C. Environment Variables
```dockerfile
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080
```

---

### 6. Resource Efficiency

#### Image Size Targets:
- **Good**: < 200MB
- **Better**: < 150MB
- **Best**: < 100MB

#### Build Time Targets:
- **Good**: < 5 minutes
- **Better**: < 2 minutes
- **Best**: < 1 minute (with cache)

---

## Dockerfile Structure Options

### Option A: Simple Single-Stage (Development)
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```
**Use**: Development only

### Option B: Multi-Stage with Security (Recommended)
```dockerfile
# Build stage
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.11-slim
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
WORKDIR /app
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appgroup . .
USER appuser
ENV PATH=/home/appuser/.local/bin:$PATH
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
```
**Use**: Production

### Option C: Alpine-Based Ultra-Minimal
```dockerfile
FROM python:3.11-alpine as builder
# ... build steps with apk instead of apt

FROM python:3.11-alpine
# ... runtime
```
**Use**: Extreme size constraints

---

## Security Scanning Tools

1. **Docker Scout** (built-in)
2. **Trivy**
3. **Snyk**
4. **Clair**

---

## Decision Needed From You:

1. **Base Image**: `python:3.11-slim` or `python:3.11-alpine`?
2. **WSGI Server**: Gunicorn, uWSGI, or Uvicorn?
3. **Build Type**: Multi-stage or single-stage?
4. **Health Check**: Include in Dockerfile or Kubernetes only?

---

## My Recommendation:
- **Base**: `python:3.11-slim` (best compatibility)
- **Server**: Gunicorn with 4 workers
- **Build**: Multi-stage for production
- **Security**: Non-root user, minimal packages, layer optimization
- **Health**: Both Dockerfile and Kubernetes (defense in depth)

This approach ensures:
- Final image ~120-150MB
- Secure by default
- Production-ready
- Fast builds with caching
