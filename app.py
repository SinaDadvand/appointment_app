"""
Embassy Appointment Scheduling System
A simple web application for scheduling visa interviews with medical exam prerequisites.
"""

import os
import sqlite3
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify, redirect, url_for
from contextlib import contextmanager
import uuid

app = Flask(__name__)

# Configuration from environment variables
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['DATABASE'] = os.getenv('DATABASE_PATH', 'appointments.db')
app.config['EMBASSY_NAME'] = os.getenv('EMBASSY_NAME', 'U.S. Embassy')
app.config['AVAILABLE_SLOTS_PER_DAY'] = int(os.getenv('AVAILABLE_SLOTS_PER_DAY', '20'))
app.config['MEDICAL_EXAM_REQUIRED'] = os.getenv('MEDICAL_EXAM_REQUIRED', 'true').lower() == 'true'
app.config['MEDICAL_EXAM_VALIDITY_DAYS'] = int(os.getenv('MEDICAL_EXAM_VALIDITY_DAYS', '180'))
app.config['APP_VERSION'] = os.getenv('APP_VERSION', '1.0.0')
app.config['ENVIRONMENT'] = os.getenv('ENVIRONMENT', 'development')

# Database context manager
@contextmanager
def get_db():
    """Get database connection with context manager."""
    conn = sqlite3.connect(app.config['DATABASE'])
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def init_db():
    """Initialize the database with required tables."""
    with get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS appointments (
                id TEXT PRIMARY KEY,
                applicant_name TEXT NOT NULL,
                email TEXT NOT NULL,
                passport_number TEXT NOT NULL,
                phone_number TEXT,
                appointment_date TEXT NOT NULL,
                appointment_time TEXT NOT NULL,
                medical_exam_date TEXT NOT NULL,
                medical_exam_verified INTEGER DEFAULT 0,
                status TEXT DEFAULT 'pending',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        ''')

# Initialize database on startup
init_db()

def validate_medical_exam(exam_date_str):
    """Validate that medical exam is recent enough."""
    try:
        exam_date = datetime.strptime(exam_date_str, '%Y-%m-%d')
        days_ago = (datetime.now() - exam_date).days
        validity_days = app.config['MEDICAL_EXAM_VALIDITY_DAYS']
        
        if days_ago < 0:
            return False, "Medical exam date cannot be in the future"
        if days_ago > validity_days:
            return False, f"Medical exam must be within the last {validity_days} days"
        
        return True, "Medical exam is valid"
    except ValueError:
        return False, "Invalid date format"

@app.route('/')
def index():
    """Main page - appointment scheduling form."""
    return render_template('index.html', 
                         embassy_name=app.config['EMBASSY_NAME'],
                         medical_required=app.config['MEDICAL_EXAM_REQUIRED'])

@app.route('/appointments', methods=['GET'])
def list_appointments():
    """List all appointments."""
    with get_db() as conn:
        cursor = conn.execute('''
            SELECT id, applicant_name, email, passport_number, 
                   appointment_date, appointment_time, status, 
                   medical_exam_date, medical_exam_verified
            FROM appointments 
            ORDER BY appointment_date DESC, appointment_time DESC
        ''')
        appointments = [dict(row) for row in cursor.fetchall()]
    
    return render_template('appointments.html', 
                         appointments=appointments,
                         embassy_name=app.config['EMBASSY_NAME'])

@app.route('/appointments', methods=['POST'])
def create_appointment():
    """Create a new appointment."""
    try:
        # Extract form data
        data = request.form
        
        # Validate required fields
        required_fields = ['applicant_name', 'email', 'passport_number', 
                          'appointment_date', 'appointment_time', 'medical_exam_date']
        for field in required_fields:
            if not data.get(field):
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        # Validate medical exam if required
        if app.config['MEDICAL_EXAM_REQUIRED']:
            is_valid, message = validate_medical_exam(data['medical_exam_date'])
            if not is_valid:
                return render_template('index.html', 
                                     error=message,
                                     embassy_name=app.config['EMBASSY_NAME'],
                                     medical_required=app.config['MEDICAL_EXAM_REQUIRED'],
                                     form_data=data), 400
        
        # Create appointment
        appointment_id = str(uuid.uuid4())
        with get_db() as conn:
            conn.execute('''
                INSERT INTO appointments 
                (id, applicant_name, email, passport_number, phone_number,
                 appointment_date, appointment_time, medical_exam_date, 
                 medical_exam_verified, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                appointment_id,
                data['applicant_name'],
                data['email'],
                data['passport_number'],
                data.get('phone_number', ''),
                data['appointment_date'],
                data['appointment_time'],
                data['medical_exam_date'],
                1,  # Auto-verify for demo
                'confirmed'
            ))
        
        return redirect(url_for('appointment_detail', appointment_id=appointment_id))
    
    except Exception as e:
        app.logger.error(f"Error creating appointment: {e}")
        return render_template('index.html', 
                             error="An error occurred while creating the appointment",
                             embassy_name=app.config['EMBASSY_NAME'],
                             medical_required=app.config['MEDICAL_EXAM_REQUIRED']), 500

@app.route('/appointments/<appointment_id>')
def appointment_detail(appointment_id):
    """Get details of a specific appointment."""
    with get_db() as conn:
        cursor = conn.execute('''
            SELECT * FROM appointments WHERE id = ?
        ''', (appointment_id,))
        appointment = cursor.fetchone()
    
    if not appointment:
        return "Appointment not found", 404
    
    return render_template('appointment_detail.html', 
                         appointment=dict(appointment),
                         embassy_name=app.config['EMBASSY_NAME'])

@app.route('/health')
def health():
    """Health check endpoint for Kubernetes liveness probe."""
    try:
        # Check database connectivity
        with get_db() as conn:
            conn.execute('SELECT 1')
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'version': app.config['APP_VERSION'],
            'environment': app.config['ENVIRONMENT']
        }), 200
    except Exception as e:
        app.logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 503

@app.route('/ready')
def ready():
    """Readiness check endpoint for Kubernetes readiness probe."""
    try:
        # Check if application is ready to serve traffic
        with get_db() as conn:
            conn.execute('SELECT COUNT(*) FROM appointments')
        
        return jsonify({
            'status': 'ready',
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        app.logger.error(f"Readiness check failed: {e}")
        return jsonify({
            'status': 'not ready',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 503

@app.route('/metrics')
def metrics():
    """Basic metrics endpoint (Prometheus-compatible format)."""
    with get_db() as conn:
        cursor = conn.execute('SELECT COUNT(*) as total FROM appointments')
        total_appointments = cursor.fetchone()[0]
        
        cursor = conn.execute("SELECT COUNT(*) as pending FROM appointments WHERE status = 'pending'")
        pending_appointments = cursor.fetchone()[0]
        
        cursor = conn.execute("SELECT COUNT(*) as confirmed FROM appointments WHERE status = 'confirmed'")
        confirmed_appointments = cursor.fetchone()[0]
    
    metrics_output = f"""# HELP appointments_total Total number of appointments
# TYPE appointments_total counter
appointments_total {total_appointments}

# HELP appointments_pending Number of pending appointments
# TYPE appointments_pending gauge
appointments_pending {pending_appointments}

# HELP appointments_confirmed Number of confirmed appointments
# TYPE appointments_confirmed gauge
appointments_confirmed {confirmed_appointments}

# HELP app_info Application information
# TYPE app_info gauge
app_info{{version="{app.config['APP_VERSION']}",environment="{app.config['ENVIRONMENT']}"}} 1
"""
    
    return metrics_output, 200, {'Content-Type': 'text/plain; charset=utf-8'}

if __name__ == '__main__':
    # Development server (not for production)
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    app.run(host='0.0.0.0', port=port, debug=debug)
