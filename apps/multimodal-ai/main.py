#!/usr/bin/env python3
# @file        apps/multimodal-ai/main.py
# @module      multimodal-ai/api
# @description Multimodal AI API — voice transcription/synthesis, LLM diagrams, vision analysis
# @governance  GOV-002: Immutable, deterministic, no hardcoded secrets
"""Unified multimodal FastAPI service for voice, diagram generation, and image analysis."""

from typing import Optional

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from diagrams import DiagramGenerator
from image_analysis import ImageAnalyzer
from voice import VoiceProcessor
from log import get_logger

logger = get_logger(__name__)

app = FastAPI(
    title="Multimodal AI",
    description="Voice transcription (Whisper), diagram generation (LLM), image analysis (LLaVA/GPT-4V)",
    version="1.0.0",
)

voice = VoiceProcessor()
diagrams = DiagramGenerator()
images = ImageAnalyzer()


# ── Response models ──────────────────────────────────────────────────────────

class TranscribeResponse(BaseModel):
    text: str
    result: dict
    # audio bytes returned as base64 via JSON when non-empty
    audio_base64: Optional[str] = None


class DiagramResponse(BaseModel):
    format: str
    code: str
    preview_url: str
    valid: bool


class ImageAnalysisResponse(BaseModel):
    error_type: str
    diagnosis: str
    fixes: list
    confidence: float


class ArchDiagramResponse(BaseModel):
    components: list
    connections: list


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.post("/voice/transcribe", response_model=TranscribeResponse)
async def transcribe_voice(audio: UploadFile = File(...)) -> TranscribeResponse:
    """
    Transcribe uploaded audio to text (Whisper), execute the command, and
    synthesize a TTS response (gTTS / Azure TTS).
    """
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file")

    text = await voice.transcribe(audio_bytes)
    result = await voice.execute_command(text)
    response_audio = await voice.synthesize_response(str(result.get("result", "")))

    import base64
    return TranscribeResponse(
        text=text,
        result=result,
        audio_base64=base64.b64encode(response_audio).decode() if response_audio else None,
    )


@app.post("/diagrams/generate", response_model=DiagramResponse)
async def generate_diagram(description: str = Form(...)) -> DiagramResponse:
    """
    Generate a Mermaid diagram from a natural language description using a local LLM.
    """
    if not description.strip():
        raise HTTPException(status_code=400, detail="Description cannot be empty")

    result = await diagrams.generate_from_description(description)
    return DiagramResponse(**result)


@app.post("/diagrams/architecture", response_model=DiagramResponse)
async def architecture_diagram(components: str = Form(...)) -> DiagramResponse:
    """
    Generate an architecture Mermaid diagram from a comma-separated list of components.
    """
    component_list = [c.strip() for c in components.split(",") if c.strip()]
    if not component_list:
        raise HTTPException(status_code=400, detail="No components provided")

    code = await diagrams.architecture_diagram(component_list)
    from diagrams import _validate_mermaid, _mermaid_live_url
    return DiagramResponse(
        format="mermaid",
        code=code,
        preview_url=_mermaid_live_url(code),
        valid=_validate_mermaid(code),
    )


@app.post("/images/analyze", response_model=ImageAnalysisResponse)
async def analyze_image(image: UploadFile = File(...)) -> ImageAnalysisResponse:
    """
    Analyze an error screenshot or UI screenshot using a vision LLM (LLaVA or GPT-4V).
    """
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty image file")

    result = await images.analyze_error_screenshot(image_bytes)
    return ImageAnalysisResponse(**result)


@app.post("/images/architecture", response_model=ArchDiagramResponse)
async def analyze_architecture(image: UploadFile = File(...)) -> ArchDiagramResponse:
    """
    Parse a hand-drawn or exported architecture diagram image and extract components.
    """
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty image file")

    result = await images.analyze_architecture_diagram(image_bytes)
    return ArchDiagramResponse(**result)


@app.get("/health")
async def health() -> dict:
    return {"status": "healthy", "service": "multimodal-ai", "version": "1.0.0"}


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import config as _cfg
    uvicorn.run(app, host=_cfg.HOST, port=_cfg.PORT, log_level=_cfg.LOG_LEVEL.lower())
