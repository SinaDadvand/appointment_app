# SQLite Database Storage - Embassy Appointment System

This document explains how appointment data is stored and persisted in the application.

---

## Overview

The Embassy Appointment System uses **SQLite** as its database, storing all appointment information in a single file. This provides simplicity for development and small-to-medium scale deployments.

**Database File**: `/data/appointments.db`

---

## Why SQLite?

### Advantages
✅ **Zero Configuration**: No separate database server required  
✅ **Portable**: Single file contains entire database  
✅ **Lightweight**: Minimal resource footprint  
✅ **ACID Compliant**: Reliable transactions  
✅ **Perfect for Development**: Quick setup in KIND/local environments  
✅ **Serverless**: Embedded directly in the application

### Limitations
❌ **Single Writer**: One connection can write at a time  
❌ **No Replication**: Built-in redundancy not available  
❌ **File-Based**: Performance limited by disk I/O  
❌ **Not for Massive Scale**: Better suited for < 100k appointments

---

## Database Schema

### Table: `appointments`

```sql
CREATE TABLE appointments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    confirmation_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    passport_number VARCHAR(50) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    medical_exam_date DATE NOT NULL,
    preferred_date DATE NOT NULL,
    preferred_time TIME NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | INTEGER | Auto-incrementing primary key |
| `confirmation_number` | VARCHAR(20) | Unique identifier (e.g., APPT-1234) |
| `full_name` | VARCHAR(255) | Applicant's full name |
| `email` | VARCHAR(255) | Contact email address |
| `passport_number` | VARCHAR(50) | Passport/travel document number |
| `phone_number` | VARCHAR(20) | Contact phone number |
| `medical_exam_date` | DATE | Date of medical examination |
| `preferred_date` | DATE | Requested appointment date |
| `preferred_time` | TIME | Requested appointment time |
| `status` | VARCHAR(20) | Appointment status (pending/confirmed/cancelled) |
| `created_at` | TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

---

## Persistence in Kubernetes

### Local Development (KIND)

The database file is stored on a **Persistent Volume** to survive pod restarts.

**Configuration** (`helm-chart/templates/pvc.yaml`):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: appointments-data
spec:
  accessModes:
    - ReadWriteOnce  # Single pod can mount
  resources:
    requests:
      storage: 1Gi   # 1GB storage allocation
```

**Mount Point** (`helm-chart/templates/deployment.yaml`):
```yaml
volumeMounts:
  - name: data
    mountPath: /data  # SQLite file location

volumes:
  - name: data
    persistentVolumeClaim:
      claimName: appointments-data
```

### Storage Lifecycle

1. **Initial Deployment**: PVC created, empty volume mounted
2. **First Run**: Application creates `appointments.db` on `/data`
3. **Pod Restart**: New pod mounts same volume, data persists
4. **Helm Upgrade**: PVC remains intact, data preserved
5. **Helm Uninstall**: PVC must be manually deleted to remove data

---

## Data Access Patterns

### Application Code (app.py)

```python
# Database initialization
DATABASE_PATH = os.getenv('DATABASE_PATH', '/data/appointments.db')
conn = sqlite3.connect(DATABASE_PATH)

# Create appointments
cursor.execute('''
    INSERT INTO appointments (confirmation_number, full_name, email, ...)
    VALUES (?, ?, ?, ...)
''', (conf_num, name, email, ...))

# Query appointments
cursor.execute('SELECT * FROM appointments WHERE status = ?', ('pending',))
appointments = cursor.fetchall()
```

### Connection Management

- **Connection Per Request**: New connection opened for each HTTP request
- **Auto-Commit**: Changes committed immediately after operations
- **Row Factory**: `sqlite3.Row` for dict-like access to results
- **Thread Safety**: SQLite handles concurrent reads, serializes writes

---

## Backup and Recovery

### Manual Backup (Development)

```powershell
# Copy database from pod
kubectl cp embassy-appointments/<pod-name>:/data/appointments.db ./backup/appointments-$(Get-Date -Format 'yyyyMMdd').db
```

### Automated Backup (Production)

**Option 1: Kubernetes CronJob**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine
            command:
            - cp
            - /data/appointments.db
            - /backup/appointments-$(date +%Y%m%d).db
```

**Option 2: Cloud Storage Integration**
- Mount Azure Blob Storage / Google Cloud Storage as volume
- Configure application to backup on write

### Restore Procedure

```powershell
# 1. Stop the application
kubectl scale deployment appointments-embassy-appointments --replicas=0

# 2. Copy backup to pod
kubectl cp ./backup/appointments.db embassy-appointments/<pod-name>:/data/appointments.db

# 3. Restart application
kubectl scale deployment appointments-embassy-appointments --replicas=1
```

---

## Migration to Production Database

For high-traffic production environments, consider migrating to a dedicated database:

### PostgreSQL Migration

```python
# Update database connection
import psycopg2

DATABASE_URL = os.getenv('DATABASE_URL')
conn = psycopg2.connect(DATABASE_URL)
```

**Helm values update**:
```yaml
database:
  type: postgresql
  host: postgres.database.svc.cluster.local
  port: 5432
  name: appointments
  username: app_user
  passwordSecret: db-credentials
```

### MySQL Migration

```python
import mysql.connector

conn = mysql.connector.connect(
    host=os.getenv('DB_HOST'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD'),
    database='appointments'
)
```

### Cloud-Native Options

- **Azure**: Azure SQL Database / Cosmos DB
- **Google Cloud**: Cloud SQL / Firestore
- **AWS**: RDS / DynamoDB

---

## Performance Considerations

### Indexing

```sql
-- Speed up common queries
CREATE INDEX idx_confirmation ON appointments(confirmation_number);
CREATE INDEX idx_email ON appointments(email);
CREATE INDEX idx_date ON appointments(preferred_date);
CREATE INDEX idx_status ON appointments(status);
```

### Connection Pooling

For higher concurrency, implement connection pooling:

```python
from sqlite3 import connect
from queue import Queue

# Connection pool
db_pool = Queue(maxsize=5)
for _ in range(5):
    db_pool.put(connect(DATABASE_PATH, check_same_thread=False))

# Get connection from pool
conn = db_pool.get()
try:
    # Execute queries
    cursor = conn.cursor()
    # ...
finally:
    db_pool.put(conn)
```

### Write-Ahead Logging (WAL)

Enable WAL mode for better concurrency:

```python
conn.execute('PRAGMA journal_mode=WAL')
```

Benefits:
- Multiple readers don't block writers
- Faster write performance
- Better crash recovery

---

## Monitoring

### Database Size

```powershell
# Check database file size
kubectl exec -it <pod-name> -n embassy-appointments -- du -h /data/appointments.db
```

### Query Performance

Add logging to track slow queries:

```python
import time

start = time.time()
cursor.execute('SELECT * FROM appointments WHERE ...')
duration = time.time() - start

if duration > 1.0:  # Log queries slower than 1 second
    logger.warning(f'Slow query: {duration}s')
```

### Storage Capacity

```powershell
# Check PVC usage
kubectl get pvc -n embassy-appointments
kubectl exec -it <pod-name> -- df -h /data
```

---

## Security

### File Permissions

```dockerfile
# In Dockerfile
RUN mkdir -p /data && \
    chown -R appuser:appuser /data && \
    chmod 750 /data
```

### Encryption at Rest

**Kubernetes Level**:
- Enable encryption for Persistent Volumes
- Use cloud provider disk encryption (Azure Disk Encryption, GCP CMEK)

**Application Level**:
- Use SQLCipher for encrypted database
```python
from pysqlcipher3 import dbapi2 as sqlite
conn = sqlite.connect(DATABASE_PATH)
conn.execute('PRAGMA key="your-encryption-key"')
```

### Access Control

- No direct database access from outside pods
- Only application pods can mount the PVC
- Use NetworkPolicies to restrict pod communication

---

## Troubleshooting

### Issue: Database Locked

**Error**: `database is locked`

**Cause**: Multiple processes attempting concurrent writes

**Solution**:
```python
# Add timeout
conn = sqlite3.connect(DATABASE_PATH, timeout=10.0)

# Or use WAL mode
conn.execute('PRAGMA journal_mode=WAL')
```

### Issue: Data Loss After Pod Restart

**Cause**: PVC not mounted correctly

**Solution**:
```powershell
# Verify PVC exists
kubectl get pvc -n embassy-appointments

# Check mount in pod
kubectl exec -it <pod-name> -- ls -la /data

# Verify deployment references PVC
kubectl describe deployment appointments-embassy-appointments
```

### Issue: Out of Disk Space

**Cause**: PVC storage limit reached

**Solution**:
```powershell
# Resize PVC (if storage class supports it)
kubectl patch pvc appointments-data -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# Or create larger PVC and migrate data
```

---

## Best Practices

1. **Regular Backups**: Automate daily backups to external storage
2. **Monitor Size**: Set alerts for database growing beyond 80% of PVC
3. **Index Wisely**: Create indexes on frequently queried columns
4. **Use WAL Mode**: Better concurrency than default journal mode
5. **Plan Migration**: Have strategy to move to production database at scale
6. **Test Recovery**: Regularly test backup restoration procedures

---

## Future Enhancements

### Planned Improvements

1. **Automatic Backups**: CronJob for daily backups to cloud storage
2. **Database Migration**: Scripts for moving to PostgreSQL/MySQL
3. **Read Replicas**: For scaling read operations
4. **Multi-Region**: Geographic distribution of data
5. **Audit Logging**: Track all database modifications

---

**Storage Type**: SQLite (file-based)  
**Current Capacity**: 1 GB  
**Recommended Production**: PostgreSQL/MySQL for > 10k appointments  
**Last Updated**: December 5, 2025
