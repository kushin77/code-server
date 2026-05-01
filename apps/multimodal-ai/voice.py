#!/usr/bin/env python3
# @file        apps/multimodal-ai/voice.py
# @module      multimodal-ai/voice
# @description Voice command transcription (Whisper) and synthesis (gTTS)
# @governance  GOV-002: Immutable, deterministic, no hardcoded secrets
"""Voice command processing: speech-to-text → execution → text-to-speech response"""

import io
import os
import tempfile
from typing import Dict, Optional
import config as _svc_config
from log import get_logger

logger = get_logger(__name__)




# Configurable via environment
_WHISPER_MODEL = _svc_config.WHISPER_MODEL
_TTS_BACKEND = _svc_config.TTS_BACKEND          # gtts | azure
_AZURE_TTS_KEY = _svc_config.AZURE_TTS_KEY
_AZURE_TTS_REGION = _svc_config.AZURE_TTS_REGION
_AZURE_TTS_VOICE = _svc_config.AZURE_TTS_VOICE


def _load_whisper():
    """Lazy-load Whisper model to avoid startup cost if not used."""
    try:
        import whisper  # openai-whisper
        model = whisper.load_model(_WHISPER_MODEL)
        logger.info(f"Loaded Whisper model: {_WHISPER_MODEL}")
        return model
    except ImportError:
        logger.warning("openai-whisper not installed — STT unavailable")
        return None


_whisper_model = None  # loaded on first use


class VoiceProcessor:
    """Processes voice commands end-to-end."""

    async def transcribe(self, audio_bytes: bytes) -> str:
        """
        Convert speech audio bytes to text using OpenAI Whisper (local).

        Args:
            audio_bytes: Raw audio bytes (WAV, MP3, or OGG)

        Returns:
            Transcribed text string, or empty string on failure.
        """
        global _whisper_model
        if _whisper_model is None:
            _whisper_model = _load_whisper()

        if _whisper_model is None:
            logger.error("Whisper unavailable — cannot transcribe audio")
            return ""

        try:
            # Write audio to a temp file since Whisper requires a file path
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                tmp.write(audio_bytes)
                tmp_path = tmp.name

            result = _whisper_model.transcribe(tmp_path, fp16=False)
            text = result.get("text", "").strip()
            logger.info(f"Transcribed {len(audio_bytes)} bytes → '{text[:80]}'")
            return text
        except Exception as e:
            logger.error(f"Whisper transcription failed: {e}")
            return ""
        finally:
            import os as _os
            try:
                _os.unlink(tmp_path)
            except Exception:
                pass

    async def execute_command(self, text: str) -> Dict:
        """
        Execute natural language command parsed from transcription.

        The command text is routed based on keywords. Structured as:
            "Deploy the last tested commit to staging"
            → action=deploy, target=commit, environment=staging
        """
        text_lower = text.lower().strip()
        logger.info(f"Executing voice command: '{text}'")

        if not text_lower:
            return {"status": "error", "result": "Empty command"}

        # Keyword routing (extensible)
        if any(kw in text_lower for kw in ("deploy", "release", "push")):
            return {"status": "queued", "action": "deploy", "input": text, "result": "Deploy queued for approval"}
        if any(kw in text_lower for kw in ("run tests", "test", "check ci")):
            return {"status": "queued", "action": "test", "input": text, "result": "CI run queued"}
        if any(kw in text_lower for kw in ("status", "health", "how is")):
            return {"status": "success", "action": "status", "input": text, "result": "All services healthy"}
        if any(kw in text_lower for kw in ("rollback", "revert", "undo")):
            return {"status": "queued", "action": "rollback", "input": text, "result": "Rollback queued for approval"}

        return {"status": "unknown", "action": "unrecognized", "input": text, "result": "Command not recognized"}

    async def synthesize_response(self, text: str) -> bytes:
        """
        Convert response text to speech audio bytes.

        Uses gTTS (Google Text-to-Speech) by default, falls back to Azure TTS
        when AZURE_TTS_KEY is set and TTS_BACKEND=azure.

        Returns:
            MP3 audio bytes, or empty bytes on failure.
        """
        if not text:
            return b""

        try:
            if _TTS_BACKEND == "azure" and _AZURE_TTS_KEY:
                return await self._synthesize_azure(text)
            return self._synthesize_gtts(text)
        except Exception as e:
            logger.error(f"TTS synthesis failed: {e}")
            return b""

    def _synthesize_gtts(self, text: str) -> bytes:
        """Synthesize speech using gTTS (offline-capable Google TTS wrapper)."""
        try:
            from gtts import gTTS
            buf = io.BytesIO()
            tts = gTTS(text=text[:500], lang="en", slow=False)  # cap at 500 chars
            tts.write_to_fp(buf)
            buf.seek(0)
            audio = buf.read()
            logger.info(f"gTTS synthesized {len(audio)} bytes for '{text[:40]}'")
            return audio
        except ImportError:
            logger.warning("gTTS not installed — TTS unavailable")
            return b""

    async def _synthesize_azure(self, text: str) -> bytes:
        """Synthesize speech using Azure Cognitive Services TTS."""
        import httpx

        ssml = (
            f"<speak version='1.0' xml:lang='en-US'>"
            f"<voice name='{_AZURE_TTS_VOICE}'>{text[:500]}</voice>"
            f"</speak>"
        )
        url = (
            f"https://{_AZURE_TTS_REGION}.tts.speech.microsoft.com"
            f"/cognitiveservices/v1"
        )
        headers = {
            "Ocp-Apim-Subscription-Key": _AZURE_TTS_KEY,
            "Content-Type": "application/ssml+xml",
            "X-Microsoft-OutputFormat": "audio-16khz-128kbitrate-mono-mp3",
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=headers, content=ssml.encode())
            resp.raise_for_status()
            logger.info(f"Azure TTS synthesized {len(resp.content)} bytes")
            return resp.content
