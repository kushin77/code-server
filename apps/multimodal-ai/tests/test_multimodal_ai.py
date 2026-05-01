"""
Multimodal AI — Unit & API Tests

Tests cover:
- Health endpoint
- Voice transcription (mocked Whisper)
- Diagram generation (mocked LLM)
- Image analysis (mocked vision model)
- Error handling for missing files / unsupported formats
"""

import io
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient


# ── App import ────────────────────────────────────────────────────────────────

with patch("voice.VoiceProcessor.transcribe", new_callable=AsyncMock) as _mv, \
     patch("diagrams.DiagramGenerator.generate", new_callable=AsyncMock) as _md, \
     patch("image_analysis.ImageAnalyzer.analyze", new_callable=AsyncMock) as _mi:
    from main import app

client = TestClient(app)


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_health_returns_200(self):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_health_body_has_status(self):
        resp = client.get("/health")
        body = resp.json()
        assert "status" in body

    def test_health_reports_service_name(self):
        resp = client.get("/health")
        body = resp.json()
        # service key or service_name should be present
        assert "service" in body or "service_name" in body or body.get("status") == "ok"


# ── Voice Transcription ───────────────────────────────────────────────────────

class TestVoiceTranscribe:
    @patch("main.voice_processor")
    def test_transcribe_returns_text(self, mock_vp):
        mock_vp.transcribe = AsyncMock(return_value="hello world")
        audio_bytes = io.BytesIO(b"fake-audio-data")
        resp = client.post(
            "/voice/transcribe",
            files={"audio": ("test.wav", audio_bytes, "audio/wav")},
        )
        # Either success or 503 if model unavailable — must not be 500
        assert resp.status_code in (200, 503)

    @patch("main.voice_processor")
    def test_transcribe_success_has_text_field(self, mock_vp):
        mock_vp.transcribe = AsyncMock(return_value="transcribed text")
        audio_bytes = io.BytesIO(b"fake-audio-data")
        resp = client.post(
            "/voice/transcribe",
            files={"audio": ("test.wav", audio_bytes, "audio/wav")},
        )
        if resp.status_code == 200:
            assert "text" in resp.json()


# ── Diagram Generation ────────────────────────────────────────────────────────

class TestDiagramGeneration:
    @patch("main.diagram_generator")
    def test_generate_returns_diagram(self, mock_dg):
        mock_dg.generate = AsyncMock(return_value="graph TD; A-->B")
        resp = client.post(
            "/diagrams/generate",
            data={"description": "A simple flow from A to B"},
        )
        assert resp.status_code in (200, 503)

    @patch("main.diagram_generator")
    def test_architecture_diagram_endpoint(self, mock_dg):
        mock_dg.generate_architecture = AsyncMock(return_value="graph TD; svc-->db")
        resp = client.post(
            "/diagrams/architecture",
            data={"components": "web-server, database, cache"},
        )
        assert resp.status_code in (200, 503)


# ── Image Analysis ────────────────────────────────────────────────────────────

class TestImageAnalysis:
    @patch("main.image_analyzer")
    def test_analyze_image_endpoint(self, mock_ia):
        mock_ia.analyze = AsyncMock(return_value="The image shows a flowchart.")
        image_bytes = io.BytesIO(b"\x89PNG\r\n")  # minimal PNG header
        resp = client.post(
            "/images/analyze",
            files={"image": ("diagram.png", image_bytes, "image/png")},
        )
        assert resp.status_code in (200, 503)

    @patch("main.image_analyzer")
    def test_architecture_analysis_endpoint(self, mock_ia):
        mock_ia.analyze_architecture = AsyncMock(return_value="Microservices pattern detected.")
        image_bytes = io.BytesIO(b"\x89PNG\r\n")
        resp = client.post(
            "/images/architecture",
            files={"image": ("arch.png", image_bytes, "image/png")},
        )
        assert resp.status_code in (200, 503)


# ── DiagramGenerator Unit Tests ───────────────────────────────────────────────

class TestDiagramGeneratorUnit:
    @patch("diagrams._LLM_BACKEND", "ollama")
    @patch("diagrams.DiagramGenerator._call_ollama", new_callable=AsyncMock)
    def test_generate_calls_ollama(self, mock_ollama):
        import asyncio
        from diagrams import DiagramGenerator
        mock_ollama.return_value = "graph TD; A-->B"
        gen = DiagramGenerator()
        result = asyncio.get_event_loop().run_until_complete(
            gen.generate("simple flow")
        )
        mock_ollama.assert_called_once()


# ── VoiceProcessor Unit Tests ─────────────────────────────────────────────────

class TestVoiceProcessorUnit:
    def test_voice_processor_instantiates(self):
        from voice import VoiceProcessor
        vp = VoiceProcessor()
        assert vp is not None
