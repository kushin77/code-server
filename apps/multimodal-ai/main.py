#!/usr/bin/env python3
# @file        apps/multimodal-ai/main.py
# @module      multimodal-ai/api
# @description Multimodal AI API (voice + diagrams + images)

"""Unified multimodal API for Phase 4 enriched IDE experience"""

from fastapi import FastAPI, File, Form
from voice import VoiceProcessor
from diagrams import DiagramGenerator
from image_analysis import ImageAnalyzer

app = FastAPI(title="Multimodal AI", version="0.1.0")

voice = VoiceProcessor()
diagrams = DiagramGenerator()
images = ImageAnalyzer()

@app.post("/voice/transcribe")
async def transcribe_voice(audio: bytes = File(...)) -> dict:
    """Transcribe voice to command"""
    text = await voice.transcribe(audio)
    result = await voice.execute_command(text)
    response_audio = await voice.synthesize_response(str(result))
    return {"text": text, "result": result, "audio": response_audio}

@app.post("/diagrams/generate")
async def generate_diagram(description: str = Form(...)) -> dict:
    """Generate diagram from description"""
    return await diagrams.generate_from_description(description)

@app.post("/images/analyze")
async def analyze_image(image: bytes = File(...)) -> dict:
    """Analyze screenshot or diagram"""
    return await images.analyze_error_screenshot(image)

@app.get("/health")
async def health() -> dict:
    return {"status": "healthy", "service": "multimodal-ai"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
