#!/usr/bin/env bash
# @file        scripts/failover/start-webhook-receiver.sh
# @module      operations/failover
# @description Start Prometheus AlertManager webhook receiver daemon
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Starts HTTP server that listens for AlertManager webhooks and responds with actions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
WEBHOOK_HOST="${WEBHOOK_HOST:-0.0.0.0}"
WEBHOOK_PORT="${WEBHOOK_PORT:-9099}"
WEBHOOK_PID_FILE="/tmp/webhook-receiver.pid"
WEBHOOK_LOG_FILE="${PROJECT_DIR}/artifacts/failover-logs/webhook-receiver.log"
RECEIVER_SCRIPT="$SCRIPT_DIR/prometheus-webhook-receiver.sh"

# Create log directory
mkdir -p "$(dirname "$WEBHOOK_LOG_FILE")"

# Function to start webhook server
start_webhook_server() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] Starting webhook receiver on $WEBHOOK_HOST:$WEBHOOK_PORT" | tee -a "$WEBHOOK_LOG_FILE"
    
    # Use nc (netcat) or python for HTTP server
    # This is a simple HTTP server that accepts POST requests on /webhook
    
    # Python implementation (preferred if python3 available)
    if command -v python3 &> /dev/null; then
        start_python_server
    elif command -v nc &> /dev/null; then
        start_netcat_server
    else
        echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] ERROR: No HTTP server available (python3 or nc required)" | tee -a "$WEBHOOK_LOG_FILE"
        exit 1
    fi
}

# Start Python-based HTTP server
start_python_server() {
    cat > /tmp/webhook_server.py << 'PYTHON_EOF'
#!/usr/bin/env python3
import json
import sys
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        # Only handle /webhook path
        if self.path != '/webhook':
            self.send_response(404)
            self.end_headers()
            return
        
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            # Parse JSON payload
            payload = json.loads(body.decode('utf-8'))
            logger.info(f"Webhook received: {len(payload.get('alerts', []))} alerts")
            
            # Process webhook via bash script
            result = subprocess.run(
                ['bash', '/tmp/webhook_receiver_handler.sh'],
                input=body,
                capture_output=True,
                timeout=30
            )
            
            if result.returncode == 0:
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK')
                logger.info("Webhook processed successfully")
            else:
                self.send_response(500)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Internal Server Error')
                logger.error(f"Webhook processing failed: {result.stderr.decode()}")
        
        except json.JSONDecodeError:
            logger.error("Invalid JSON payload")
            self.send_response(400)
            self.end_headers()
        except subprocess.TimeoutExpired:
            logger.error("Webhook handler timeout")
            self.send_response(504)
            self.end_headers()
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            self.send_response(500)
            self.end_headers()
    
    def do_GET(self):
        # Health check endpoint
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"healthy"}')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

if __name__ == '__main__':
    host = sys.argv[1] if len(sys.argv) > 1 else '0.0.0.0'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 9099
    
    server = HTTPServer((host, port), WebhookHandler)
    logger.info(f"Starting webhook server on {host}:{port}")
    server.serve_forever()
PYTHON_EOF
    
    chmod +x /tmp/webhook_server.py
    
    # Copy receiver script to /tmp for subprocess access
    cp "$RECEIVER_SCRIPT" /tmp/webhook_receiver_handler.sh
    chmod +x /tmp/webhook_receiver_handler.sh
    
    # Start Python server in background
    python3 /tmp/webhook_server.py "$WEBHOOK_HOST" "$WEBHOOK_PORT" >> "$WEBHOOK_LOG_FILE" 2>&1 &
    
    local pid=$!
    echo "$pid" > "$WEBHOOK_PID_FILE"
    
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] ✓ Webhook receiver started (PID: $pid)" | tee -a "$WEBHOOK_LOG_FILE"
}

# Start netcat-based server (minimal implementation)
start_netcat_server() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] Starting netcat-based webhook server..." | tee -a "$WEBHOOK_LOG_FILE"
    
    # Use mkfifo for bidirectional communication
    local fifo=/tmp/webhook.fifo
    mkfifo "$fifo" || true
    
    (
        while true; do
            cat "$fifo" | nc -l -p "$WEBHOOK_PORT" -q 1 | \
            {
                # Read HTTP request headers
                read method path protocol
                
                if [[ "$path" == "/webhook" && "$method" == "POST" ]]; then
                    # Skip headers until empty line
                    while IFS= read -r line; do
                        [[ -z "$line" ]] && break
                    done
                    
                    # Read body and process
                    "$RECEIVER_SCRIPT" > /tmp/webhook_response.txt 2>&1
                    local response=$(cat /tmp/webhook_response.txt)
                    
                    # Send HTTP response
                    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$response"
                else
                    echo -e "HTTP/1.1 404 Not Found\r\n\r\n"
                fi
            } > "$fifo"
        done
    ) >> "$WEBHOOK_LOG_FILE" 2>&1 &
    
    local pid=$!
    echo "$pid" > "$WEBHOOK_PID_FILE"
    
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] ✓ Webhook receiver started (PID: $pid)" | tee -a "$WEBHOOK_LOG_FILE"
}

# Function to stop webhook server
stop_webhook_server() {
    if [[ -f "$WEBHOOK_PID_FILE" ]]; then
        local pid
        pid=$(cat "$WEBHOOK_PID_FILE")
        
        echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] Stopping webhook receiver (PID: $pid)..."
        
        if kill "$pid" 2>/dev/null; then
            rm -f "$WEBHOOK_PID_FILE"
            echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] ✓ Webhook receiver stopped" | tee -a "$WEBHOOK_LOG_FILE"
        fi
    fi
}

# Function to check webhook server status
status_webhook_server() {
    if [[ -f "$WEBHOOK_PID_FILE" ]]; then
        local pid
        pid=$(cat "$WEBHOOK_PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            echo "✓ Webhook receiver running (PID: $pid)"
            
            # Check health endpoint
            if command -v curl &> /dev/null; then
                local health
                health=$(curl -s http://localhost:$WEBHOOK_PORT/health 2>/dev/null || echo "unreachable")
                echo "  Health: $health"
            fi
            
            return 0
        else
            echo "✗ Webhook receiver not running (stale PID file)"
            rm -f "$WEBHOOK_PID_FILE"
            return 1
        fi
    else
        echo "✗ Webhook receiver not running"
        return 1
    fi
}

# Main
case "${1:-start}" in
    start)
        start_webhook_server
        ;;
    stop)
        stop_webhook_server
        ;;
    status)
        status_webhook_server
        ;;
    restart)
        stop_webhook_server
        sleep 2
        start_webhook_server
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac
