# Multimodal AI Service

**Issue:** #1563 Phase 3 - Multimodal AI Integration  
**Status:** ✅ IMPLEMENTATION COMPLETE  
**Framework:** FastAPI + OpenAI Whisper + LLaVA + gTTS  
**Python:** 3.11+

## Overview

The Multimodal AI Service provides a unified API for processing multiple modalities: voice (transcription/synthesis), image analysis, and diagram generation. It enables agents to interact via voice commands, analyze screenshots, and generate architecture diagrams using LLM intelligence.

### Key Features

- **Voice Processing**: Speech-to-text (Whisper) and text-to-speech (gTTS/Azure TTS)
- **Image Analysis**: Visual understanding with LLaVA or GPT-4V for troubleshooting
- **Diagram Generation**: Architecture and flow diagram generation from prompts
- **Command Execution**: Natural language command parsing and execution
- **Flexible Backends**: Support for multiple TTS, LLM, and analysis providers
- **Audit Logging**: All processing logged for compliance (GOV-002)

## Architecture

### Core Components

#### 1. **FastAPI Application** (`main.py`)
- RESTful API for all multimodal operations
- Unified response models for consistency
- File upload handling for audio/images
- Base64 encoding for media in JSON responses

#### 2. **Voice Processor** (`voice.py`)
- Whisper model integration for speech recognition
- Natural language command parsing
- Command execution framework
- Multiple TTS backends (gTTS, Azure)
- Audio synthesis and streaming

#### 3. **Image Analyzer** (`image_analysis.py`)
- Visual understanding of screenshots/diagrams
- Error diagnosis from system screenshots
- Visual troubleshooting guidance
- Multiple vision models (LLaVA, GPT-4V)

#### 4. **Diagram Generator** (`diagrams.py`)
- Architecture diagram generation from prompts
- LLM-powered layout and component selection
- Support for multiple output formats
- Validation and preview generation

### API Endpoints

```
POST /voice/transcribe                 # Transcribe audio to text + execute + respond
POST /voice/synthesize                 # Generate speech from text
GET  /voice/commands                   # List available voice commands
POST /image/analyze                    # Analyze image for errors/solutions
POST /diagram/generate                 # Generate architecture diagram
POST /diagram/validate                 # Validate diagram specification
GET  /health                           # Health check
```

## Data Models

### Voice Operations

#### Transcribe Request
```python
{
    "audio": <binary audio data>,    # MultiPart file upload
    "language": "en"                 # Optional language code
}
```

#### Transcribe Response
```python
{
    "text": "Deploy the authentication server",
    "result": {
        "command": "deploy",
        "target": "auth-server",
        "status": "pending"
    },
    "audio_base64": "//NExAAqQIL..."  # Optional synthesized response
}
```

### Image Analysis

#### Analyze Request
```python
{
    "image": <binary image data>,       # PNG/JPEG upload
    "context": "Error in deployment"    # Optional context
}
```

#### Analyze Response
```python
{
    "error_type": "connection_timeout",
    "diagnosis": "Service failed to respond within 30 seconds",
    "fixes": [
        "Increase timeout to 60 seconds",
        "Check network connectivity",
        "Verify service is running"
    ],
    "confidence": 0.92
}
```

### Diagram Generation

#### Generate Request
```python
{
    "prompt": "Show the authentication flow with 3 components",
    "format": "mermaid",              # mermaid, graphviz, ascii
    "style": "detailed"               # simple, detailed, technical
}
```

#### Generate Response
```python
{
    "format": "mermaid",
    "code": "graph TD\n    A[Client]...",
    "preview_url": "http://..../preview",
    "valid": true
}
```

## Voice Commands

### Supported Commands

| Command | Example | Action |
|---------|---------|--------|
| **deploy** | "Deploy the auth-server" | Trigger deployment pipeline |
| **status** | "What's the deployment status?" | Check system status |
| **rollback** | "Rollback to version 1.2.3" | Initiate rollback |
| **logs** | "Show me the error logs" | Stream service logs |
| **query** | "Query the memory engine for incidents" | Semantic search |
| **alert** | "Acknowledge the alert" | Alert management |

## Getting Started

### Prerequisites

- Python 3.11+
- FastAPI 0.124+
- OpenAI Whisper or local whisper.cpp
- gTTS or Azure TTS API key
- LLaVA or GPT-4V for image analysis
- Docker & Docker Compose (recommended)

### Installation

1. **Install dependencies**:
```bash
cd apps/multimodal-ai
pip install -r requirements.txt

# Optional: OpenAI dependencies
pip install openai-whisper>=20231226
pip install pillow>=10.0.0
```

2. **Configure environment**:
```bash
# Create .env file
cat > .env << EOF
WHISPER_MODEL=base              # tiny, base, small, medium, large
TTS_BACKEND=gtts               # gtts or azure
AZURE_TTS_KEY=<your-key>       # If using Azure TTS
AZURE_TTS_REGION=eastus
AZURE_TTS_VOICE=en-US-JennyNeural
IMAGE_ANALYSIS_MODEL=llava     # llava or gpt4v
OPENAI_API_KEY=<your-key>      # If using GPT-4V
EOF
```

### Running Locally

```bash
# Development (with reload)
cd apps/multimodal-ai
uvicorn main:app --reload --host 0.0.0.0 --port 8082

# Or via Docker Compose
docker compose -f docker-compose.yml up multimodal-ai
```

### Health Check

```bash
curl http://localhost:8082/health
# Response: {"status": "healthy", "models_loaded": 1}
```

## API Usage Examples

### Voice Transcription & Command Execution

```bash
# Record audio (macOS example)
sox -n -t wav - | sox - audio.wav rate 16000

# Transcribe and execute command
curl -X POST http://localhost:8082/voice/transcribe \
  -F "audio=@audio.wav"

# Response:
{
  "text": "Deploy the authentication server",
  "result": {
    "command": "deploy",
    "target": "auth-server",
    "status": "triggered"
  },
  "audio_base64": "//NExAAqQIL..."
}
```

### Image Analysis

```bash
# Analyze a screenshot for troubleshooting
curl -X POST http://localhost:8082/image/analyze \
  -F "image=@error-screenshot.png" \
  -F "context=Service error in deployment"

# Response:
{
  "error_type": "connection_refused",
  "diagnosis": "The service failed to bind to port 8001",
  "fixes": [
    "Check if port 8001 is already in use",
    "Try a different port",
    "Verify firewall rules"
  ],
  "confidence": 0.88
}
```

### Diagram Generation

```bash
curl -X POST http://localhost:8082/diagram/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Three-tier architecture with database, API, and frontend",
    "format": "mermaid",
    "style": "detailed"
  }'

# Response:
{
  "format": "mermaid",
  "code": "graph TD\n  DB[(PostgreSQL)]\n  API[API Server]\n  FE[Frontend]\n  DB --> API\n  API --> FE",
  "preview_url": "http://localhost:8082/diagram/preview/xyz",
  "valid": true
}
```

### Text-to-Speech Synthesis

```bash
curl -X POST http://localhost:8082/voice/synthesize \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Deployment completed successfully",
    "language": "en",
    "voice": "female"
  }'

# Response:
{
  "audio_base64": "//NExAAqQIL...",
  "duration_ms": 2345,
  "format": "wav"
}
```

## Configuration

### Environment Variables

```bash
# Voice Processing
WHISPER_MODEL=base              # Model size: tiny, base, small, medium, large
TTS_BACKEND=gtts               # Text-to-speech: gtts or azure
WHISPER_LANGUAGE=en            # Default language for transcription

# Azure TTS (if TTS_BACKEND=azure)
AZURE_TTS_KEY=<key>
AZURE_TTS_REGION=eastus
AZURE_TTS_VOICE=en-US-JennyNeural

# Image Analysis
IMAGE_ANALYSIS_MODEL=llava     # Vision model: llava or gpt4v
OPENAI_API_KEY=<key>           # For GPT-4V
LLAVA_ENDPOINT=http://...      # For local LLaVA

# Diagram Generation
DIAGRAM_FORMAT=mermaid         # Default format
DIAGRAM_STYLE=detailed         # Default style
```

### Model Selection Guide

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| **tiny** | 39M | ⚡⚡⚡ | 70% | Real-time, low resources |
| **base** | 140M | ⚡⚡ | 75% | General purpose (default) |
| **small** | 244M | ⚡ | 82% | Better accuracy |
| **medium** | 769M | 🐢 | 87% | High accuracy |
| **large** | 1.5B | 🐢🐢 | 93% | Maximum accuracy |

## Governance & Compliance

**GOV-002: Immutable & Deterministic Processing**
- All voice/image processing is deterministic and logged
- No hardcoded secrets (use environment variables)
- Processing results are auditable
- Sensitive information is redacted appropriately

## Integration Patterns

### 1. Voice Command Execution
```python
from multimodal_ai import VoiceProcessor

processor = VoiceProcessor()

# Transcribe and execute
with open("command.wav", "rb") as f:
    result = await processor.transcribe(f.read())
    
# Get synthesized response
audio = await processor.synthesize_response(result["status"])
```

### 2. Automated Error Analysis
```python
from multimodal_ai import ImageAnalyzer

analyzer = ImageAnalyzer()

# Analyze error screenshot
with open("error.png", "rb") as f:
    analysis = await analyzer.analyze(
        f.read(),
        context="Deployment failed"
    )
    
# Use analysis for automated recovery
if analysis["error_type"] == "connection_refused":
    perform_recovery_action("retry_with_backoff")
```

### 3. Architecture Documentation
```python
from multimodal_ai import DiagramGenerator

generator = DiagramGenerator()

# Auto-generate architecture from description
diagram = await generator.generate(
    prompt="Current production infrastructure",
    format="mermaid"
)

# Save for documentation
save_diagram_to_docs(diagram["code"])
```

## Performance Tuning

### Model Caching
- Whisper model cached in memory (loaded once)
- Vision models loaded on-demand
- Cache cleared on service restart

### Batch Processing
```python
# Batch voice processing for efficiency
results = await processor.transcribe_batch([audio1, audio2, audio3])
```

### Streaming Responses
- Long audio responses streamed via chunked encoding
- Large diagrams paginated for performance

## Monitoring & Observability

### Health Check Metrics

```bash
curl http://localhost:8082/health

# Response:
{
  "status": "healthy",
  "models_loaded": 2,
  "last_update": "2026-04-28T12:00:00Z",
  "uptime_seconds": 3600
}
```

### Log Levels

```bash
# Development (verbose)
LOG_LEVEL=DEBUG

# Production (info)
LOG_LEVEL=INFO

# Errors only
LOG_LEVEL=ERROR
```

## Production Deployment Checklist

- [ ] GPU/CUDA available for Whisper inference (optional but recommended)
- [ ] TTS backend configured (gTTS or Azure TTS)
- [ ] Image analysis model deployed (LLaVA or GPT-4V API key)
- [ ] Audio file size limits enforced (max 25MB)
- [ ] Image file size limits enforced (max 10MB)
- [ ] Rate limiting configured (100 req/min)
- [ ] Request logging and audit trail enabled
- [ ] Error handling and graceful degradation implemented
- [ ] Model fallbacks configured

## Known Limitations

- **Cold Start**: First request loads model (2-10 seconds depending on model)
- **GPU Memory**: Large models (medium/large) require 6+ GB VRAM
- **Audio Quality**: Best results with 16kHz mono audio
- **Image Resolution**: Optimal with 800x600 or higher
- **Diagram Complexity**: Limited to 50 components per diagram
- **Language Support**: Optimized for English, other languages supported but less accurate

## Development & Testing

### Run Test Suite

```bash
cd apps/multimodal-ai
pytest test_multimodal_ai.py -v

# Or with coverage
pytest test_multimodal_ai.py --cov=. --cov-report=html
```

### Test Voice Command

```bash
# Generate test audio (5 seconds of silence)
ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 5 -q:a 9 -acodec libmp3lame test.mp3

# Or use actual audio file
curl -X POST http://localhost:8082/voice/transcribe \
  -F "audio=@test.mp3"
```

## Troubleshooting

### Issue: "Model loading failed"
```bash
# Verify model is available
python -c "import whisper; whisper.load_model('base')"

# Or download explicitly
whisper --model base --task transcribe dummy.mp3
```

### Issue: "Audio format not supported"
- Convert to WAV 16kHz mono
  ```bash
  ffmpeg -i audio.mp3 -acodec pcm_s16le -ar 16000 audio.wav
  ```

### Issue: "GPU memory exceeded"
- Use smaller model: `WHISPER_MODEL=tiny`
- Enable CPU inference: `CUDA_VISIBLE_DEVICES=""`

### Issue: "Azure TTS connection failed"
- Verify API key: `echo $AZURE_TTS_KEY | wc -c` (should be ~90 chars)
- Check region: `AZURE_TTS_REGION=eastus`
- Try gTTS fallback: `TTS_BACKEND=gtts`

## Architecture Diagram

```
┌───────────────────────────────────────────┐
│ FastAPI Application (port 8082)           │
│  - /voice/transcribe                      │
│  - /voice/synthesize                      │
│  - /image/analyze                         │
│  - /diagram/generate                      │
└─────────┬───────────┬───────────┬─────────┘
          │           │           │
    ┌─────▼──┐  ┌─────▼──┐  ┌────▼────┐
    │ Whisper│  │ LLaVA/ │  │ Diagram │
    │ (STT)  │  │ GPT-4V │  │Generator│
    │        │  │ (Vision)  │ (LLM)   │
    └────────┘  └────────┘  └─────────┘
   port 8000   port 9000   (local)
```

## References

- [OpenAI Whisper](https://github.com/openai/whisper)
- [gTTS Documentation](https://gtts.readthedocs.io/)
- [LLaVA Vision Model](https://github.com/haotian-liu/LLaVA)
- [Mermaid Diagram Syntax](https://mermaid.live/)
- [GOV-002: Compliance](../GOVERNANCE.md)
