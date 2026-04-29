FROM python:3.11-alpine

WORKDIR /app

# Install curl for healthchecks
RUN apk add --no-cache curl

# Copy and install requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1000 activity && adduser -D -u 1000 -G activity activity

USER activity

EXPOSE 8004

CMD ["python", "main.py"]
