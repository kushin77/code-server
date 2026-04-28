# Paperclip Service

File and attachment storage system for Code Server Enterprise. Provides secure file management, versioning, deduplication, and distributed storage for user uploads and system artifacts.

## Architecture Overview

Paperclip Service provides:

- **File Storage**: Reliable file storage with multiple backends (S3, local, hybrid)
- **Versioning**: Track file versions with full history
- **Deduplication**: Content-aware deduplication to reduce storage cost
- **Access Control**: Fine-grained permissions for file access
- **Encryption**: End-to-end encryption support with key management
- **Virus Scanning**: Automatic malware scanning on upload
- **CDN Integration**: Cached distribution via CDN for public files
- **Metadata Extraction**: Automatic metadata and thumbnail generation

## Service Dependencies

```
paperclip (File Storage)
├── PostgreSQL (metadata_db, files table, versions table)
├── S3 / MinIO (object storage)
├── Redis (upload cache, virus scan queue)
├── CDN (cached distribution, public URLs)
├── auth-server (verify file access permissions)
├── ClamAV (virus scanning)
└── ImageMagick (thumbnail generation)
```

## Core Components

### 1. File Upload Manager

```python
# Example: Upload file
POST /files/upload
{
    "filename": "project-architecture.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 2048576,
    "owner_id": "user-001",
    "tags": ["architecture", "documentation"],
    "public": false,
    "expires_at": "2026-06-28T00:00:00Z"
}

# Response includes upload URL and session
Response:
{
    "upload_id": "upload-001",
    "file_id": "file-001",
    "upload_url": "s3://code-server/uploads/upload-001",
    "upload_token": "token-abc123",
    "chunk_size": 5242880,  # 5MB chunks
    "total_chunks": 1,
    "expires_in_seconds": 3600
}
```

### 2. Virus Scanner

```python
# Example: Scan uploaded file
POST /files/{file_id}/scan
{
    "scan_mode": "quick|full"
}

Response:
{
    "file_id": "file-001",
    "scan_status": "in_progress",
    "scan_id": "scan-001",
    "estimated_duration_seconds": 30
}

# Poll for scan results
GET /files/{file_id}/scan/scan-001

Response:
{
    "scan_id": "scan-001",
    "status": "completed",
    "clean": true,
    "threats_detected": 0,
    "scan_timestamp": "2026-04-28T10:05:00Z"
}
```

### 3. File Versioning

```python
# Example: Get file versions
GET /files/{file_id}/versions

Response:
{
    "file_id": "file-001",
    "versions": [
        {
            "version_id": "v-001",
            "version_number": 3,
            "filename": "project-architecture.pdf",
            "size_bytes": 2048576,
            "created_at": "2026-04-28T10:00:00Z",
            "created_by": "user-001",
            "change_summary": "Updated architecture diagram"
        },
        {
            "version_id": "v-002",
            "version_number": 2,
            "created_at": "2026-04-27T15:00:00Z"
        }
    ],
    "current_version": "v-001"
}
```

### 4. Metadata Extractor

```python
# Example: Get file metadata
GET /files/{file_id}/metadata

Response:
{
    "file_id": "file-001",
    "filename": "project-architecture.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 2048576,
    "created_at": "2026-04-28T10:00:00Z",
    "modified_at": "2026-04-28T10:00:00Z",
    "owner_id": "user-001",
    "metadata": {
        "page_count": 42,
        "created_by_app": "Adobe Acrobat",
        "creation_date": "2026-04-20",
        "keywords": ["architecture", "deployment"]
    },
    "checksums": {
        "md5": "abc123...",
        "sha256": "def456..."
    },
    "thumbnail_url": "https://cdn.code-server.com/files/file-001/thumb.png"
}
```

### 5. Access Control

```python
# Example: Share file with user
POST /files/{file_id}/share
{
    "share_with": {
        "user_id": "user-002",
        "permissions": ["read"],
        "expires_at": "2026-05-28T00:00:00Z"
    }
}

Response:
{
    "file_id": "file-001",
    "share_id": "share-001",
    "shared_with": "user-002",
    "permissions": ["read"],
    "created_at": "2026-04-28T10:00:00Z",
    "expires_at": "2026-05-28T00:00:00Z"
}
```

## API Endpoints

### File Operations

```bash
# Upload file
POST /files/upload
{
    "filename": "...",
    "mime_type": "...",
    "size_bytes": 12345
}

# Get file (download)
GET /files/{file_id}

# Get file metadata
GET /files/{file_id}/metadata

# Update file metadata
PUT /files/{file_id}/metadata
{
    "tags": [...],
    "description": "..."
}

# Delete file
DELETE /files/{file_id}

# Restore deleted file
POST /files/{file_id}/restore
```

### Versioning

```bash
# List versions
GET /files/{file_id}/versions

# Get specific version
GET /files/{file_id}/versions/{version_id}

# Download version
GET /files/{file_id}/versions/{version_id}/download

# Revert to version
POST /files/{file_id}/versions/{version_id}/revert
```

### Virus Scanning

```bash
# Scan file
POST /files/{file_id}/scan
{
    "scan_mode": "quick|full"
}

# Get scan results
GET /files/{file_id}/scan/{scan_id}

# Get scan history
GET /files/{file_id}/scan-history
```

### Sharing & Permissions

```bash
# Share file
POST /files/{file_id}/share
{...}

# Get file shares
GET /files/{file_id}/shares

# Update share permissions
PUT /files/{file_id}/shares/{share_id}
{
    "permissions": ["read", "write"]
}

# Revoke share
DELETE /files/{file_id}/shares/{share_id}
```

### Search & Listing

```bash
# List user's files
GET /files?owner_id=user-001&limit=50&offset=0

# Search files
GET /search?query=architecture&created_by=user-001&tags=documentation

# Get file statistics
GET /stats
{
    "total_storage_bytes": 1099511627776,
    "total_files": 50000,
    "files_by_type": {
        "pdf": 15000,
        "docx": 10000,
        "txt": 25000
    }
}
```

## Configuration

### Environment Variables

```bash
# Storage Backend
PAPERCLIP_STORAGE_BACKEND=s3|local|hybrid
PAPERCLIP_S3_BUCKET=code-server-files
PAPERCLIP_S3_REGION=us-east-1
PAPERCLIP_S3_ENDPOINT=https://s3.amazonaws.com

# Local Storage (for local/hybrid)
PAPERCLIP_LOCAL_STORAGE_PATH=/var/lib/paperclip/storage
PAPERCLIP_LOCAL_CACHE_PATH=/var/cache/paperclip

# Database
PAPERCLIP_DB_URL=postgresql://user:pass@localhost:5432/paperclip_db
PAPERCLIP_DB_POOL_SIZE=20

# Redis
PAPERCLIP_REDIS_URL=redis://localhost:6379/0

# Security
PAPERCLIP_ENCRYPTION_ENABLED=true
PAPERCLIP_ENCRYPTION_KEY_ID=current-key
PAPERCLIP_VIRUS_SCAN_ENABLED=true
PAPERCLIP_CLAMAV_SOCKET=unix:///var/run/clamav/clamd.ctl

# File Limits
PAPERCLIP_MAX_FILE_SIZE_BYTES=5368709120  # 5GB
PAPERCLIP_CHUNK_SIZE_BYTES=5242880  # 5MB
PAPERCLIP_RETENTION_DAYS=365

# CDN
PAPERCLIP_CDN_ENABLED=true
PAPERCLIP_CDN_ENDPOINT=https://cdn.code-server.com
```

### Docker Compose Configuration

```yaml
paperclip:
  image: kushin77/code-server-paperclip@sha256:abc456...
  ports:
    - "8018:8000"
  environment:
    - PAPERCLIP_STORAGE_BACKEND=s3
    - PAPERCLIP_S3_BUCKET=code-server-files
    - PAPERCLIP_DB_URL=postgresql://postgres:password@postgres:5432/paperclip_db
    - PAPERCLIP_VIRUS_SCAN_ENABLED=true
  depends_on:
    - postgres
    - redis
    - clamav
  volumes:
    - /var/cache/paperclip:/var/cache/paperclip
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s

clamav:
  image: clamav/clamav:latest
  volumes:
    - clamav-db:/var/lib/clamav
```

## File Type Support

### Documents

```
pdf, doc, docx, odt, rtf, txt, md
```

### Spreadsheets

```
xls, xlsx, ods, csv
```

### Presentations

```
ppt, pptx, odp
```

### Images

```
jpg, jpeg, png, gif, webp, svg, bmp, tiff
```

### Archives

```
zip, tar, gz, rar, 7z
```

### Code

```
py, js, ts, java, go, rust, cpp, c, h, hpp
```

## Deduplication Strategy

### Content-Based Deduplication

```python
{
    "enabled": true,
    "algorithm": "sha256",
    "min_file_size_bytes": 1024,  # Only dedupe files > 1KB
    "storage_savings_percent": 35
}

# Example: Two identical files
# - File A (10MB) stored normally
# - File B (10MB) same content, stored as reference to File A
# - Storage used: 10MB instead of 20MB
```

## Virus Scanning Pipeline

### Upload Flow

```
File Upload
    ↓
Chunked Upload
    ↓
Store to Temporary Location
    ↓
Queue for Virus Scan
    ↓
ClamAV Scanning
    ↓
Move to Permanent Storage (if clean)
    ↓
Generate Thumbnails
    ↓
Extract Metadata
    ↓
File Ready
```

## Monitoring & Observability

### Key Metrics

```
paperclip_files_uploaded_total
paperclip_files_deleted_total
paperclip_storage_bytes_total
paperclip_virus_scan_passed_total
paperclip_virus_scan_failed_total
paperclip_deduplication_savings_bytes
paperclip_upload_time_seconds
paperclip_download_time_seconds
paperclip_thumbnail_generation_time_ms
```

## Production Deployment Checklist

- [ ] S3 bucket configured with versioning
- [ ] PostgreSQL database initialized
- [ ] Redis cache operational
- [ ] ClamAV service running and up-to-date
- [ ] Encryption keys rotated and managed
- [ ] CDN configured and tested
- [ ] Backup procedures for metadata and files
- [ ] Monitoring and alerting configured
- [ ] Storage quotas per user configured
- [ ] File retention policies configured
- [ ] Team trained on operations

## Integration Examples

### With Auth-Server

```python
# Verify user can access file
GET /auth-server/verify-access
{
    "user": "user-002",
    "resource": "file-001",
    "action": "read"
}
```

### With Activity Feed

```python
# File upload event
{
    "event_type": "file_uploaded",
    "file_id": "file-001",
    "filename": "project-architecture.pdf",
    "size_bytes": 2048576,
    "owner_id": "user-001",
    "timestamp": "2026-04-28T10:00:00Z"
}
```

## Related Services

- **auth-server**: File access permissions
- **activity-feed**: File operation events
- **memory-engine**: Store and retrieve documents for learning

## Support & Documentation

For additional support, see:

- [File Management Guide](../../COMPLETE_35_SERVICE_REFERENCE.md)
- [Storage Architecture](../../COMPLETE_DEPLOYMENT_PROGRAM_SUMMARY.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: storage

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026
