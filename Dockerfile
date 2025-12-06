# Build stage
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.11-slim

# Add labels for metadata
LABEL maintainer="embassy-appointments" \
      version="1.0.0" \
      description="Embassy Appointment Scheduling System"

# Create non-root user
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -u 1000 appuser

WORKDIR /app

# Install runtime dependencies (curl for healthcheck)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appgroup . .

# Set environment variables
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    WORKERS=4

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application with Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
