# Application Requirements & Design Decisions

## Overview
Building a mock embassy visa interview appointment scheduling system with medical exam prerequisite.

---

## 1. Application Framework Options

### Option A: Flask (Recommended)
**Pros:**
- Lightweight and simple for this use case
- Excellent for microservices
- Fast development
- Minimal overhead

**Cons:**
- Less built-in features than Django
- Manual configuration needed

### Option B: FastAPI
**Pros:**
- Modern async support
- Auto-generated API documentation
- Type hints and validation
- Better performance for I/O operations

**Cons:**
- Might be overkill for simple app
- Requires Python 3.7+

### Option C: Django
**Pros:**
- Full-featured framework
- Built-in admin panel
- ORM included

**Cons:**
- Heavier footprint
- More complex for simple apps

---

## 2. HTTP Endpoints Design

### Required Endpoints (Minimum 2):

#### Endpoint 1: Main Application
- `GET /` - Main page (appointment scheduling form)
- `POST /appointments` - Create new appointment
- `GET /appointments` - List all appointments
- `GET /appointments/<id>` - Get specific appointment

#### Endpoint 2: Health Check
- `GET /health` - Health check endpoint
- Returns: `{"status": "healthy", "timestamp": "...", "version": "1.0.0"}`

#### Additional Endpoints (Optional):
- `GET /ready` - Readiness probe
- `GET /metrics` - Prometheus metrics (optional)
- `DELETE /appointments/<id>` - Cancel appointment
- `PUT /appointments/<id>` - Update appointment

---

## 3. Environment Variables

### Required Configuration:
```bash
# Application Settings
APP_NAME=embassy-appointment-system
APP_VERSION=1.0.0
ENVIRONMENT=production  # or development, staging
PORT=8080
DEBUG=false

# Database (if used)
DATABASE_URL=sqlite:///appointments.db  # or PostgreSQL connection string

# Embassy Settings
EMBASSY_NAME=US Embassy
AVAILABLE_SLOTS_PER_DAY=20
MEDICAL_EXAM_REQUIRED=true

# Security
SECRET_KEY=<random-secret-key>
ALLOWED_ORIGINS=*  # CORS settings
```

---

## 4. Application Features

### Core Features:
1. **Appointment Scheduling**
   - Select appointment date/time
   - Provide personal information
   - Medical exam verification

2. **Medical Exam Prerequisite**
   - Check if medical exam is completed
   - Store medical exam date
   - Validate exam is recent (within last 6 months)

3. **Data Display**
   - View all appointments
   - Search/filter appointments
   - Export functionality (optional)

### Data Model:
```python
Appointment:
  - id: UUID
  - applicant_name: String
  - email: String
  - passport_number: String
  - appointment_date: DateTime
  - medical_exam_date: DateTime
  - medical_exam_verified: Boolean
  - status: String (pending, confirmed, cancelled)
  - created_at: DateTime
  - updated_at: DateTime
```

---

## 5. Frontend Options

### Option A: HTML Templates with Bootstrap (Recommended)
**Pros:**
- Simple and lightweight
- No build process needed
- Works directly with Flask/FastAPI
- Responsive out of the box

**Cons:**
- Less interactive than SPA

### Option B: HTML + Tailwind CSS
**Pros:**
- Modern utility-first CSS
- Highly customizable
- Smaller final CSS size

**Cons:**
- Requires build step (optional)

### Option C: React/Vue SPA
**Pros:**
- Rich interactivity
- Better UX

**Cons:**
- Adds complexity
- Separate build process
- Larger container size

---

## 6. Data Storage Options

### Option A: SQLite (Recommended for Demo)
**Pros:**
- No external dependencies
- Perfect for demos
- Easy to containerize

**Cons:**
- Not suitable for high concurrency
- Single file

### Option B: PostgreSQL
**Pros:**
- Production-ready
- ACID compliant
- Better for multiple replicas

**Cons:**
- Requires separate container/service
- More complex setup

### Option C: In-Memory (with persistence)
**Pros:**
- Fast
- Simple

**Cons:**
- Data loss on restart (unless persisted)

---

## Decision Needed From You:

1. **Framework**: Flask, FastAPI, or Django?
2. **Frontend**: Bootstrap, Tailwind, or React?
3. **Storage**: SQLite, PostgreSQL, or In-Memory?
4. **Additional Features**: Do you want metrics endpoint, appointment cancellation, email notifications (mock)?

---

## My Recommendation:
- **Framework**: Flask (simplicity + perfect for containerization)
- **Frontend**: HTML + Bootstrap (simple, responsive, no build step)
- **Storage**: SQLite (easy demo, can be upgraded to PostgreSQL later)
- **Features**: Core features + health/ready endpoints + basic metrics

This combination keeps the container small, deployment simple, and meets all requirements while being production-ready with minimal changes.
