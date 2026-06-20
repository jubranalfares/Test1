"""
Jarvis AI Engine - Port 8001
Handles all AI operations: LLM chat, STT, TTS, intelligence extraction.
"""

import os
import io
import json
import time
import logging
import tempfile
import subprocess
import shutil
from datetime import datetime
from typing import Optional

import httpx
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response, JSONResponse
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
WHISPER_MODEL = os.getenv("WHISPER_MODEL", "base")
ASSISTANT_LANGUAGE = os.getenv("ASSISTANT_LANGUAGE", "de")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ai-engine")

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis AI Engine", version="1.0.0")

# ---------------------------------------------------------------------------
# Lazy-loaded singletons
# ---------------------------------------------------------------------------
_whisper_model = None
_groq_client = None


def get_whisper_model():
    global _whisper_model
    if _whisper_model is None:
        try:
            from faster_whisper import WhisperModel
            import torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
            compute_type = "float16" if device == "cuda" else "int8"
            logger.info(f"Loading Whisper model '{WHISPER_MODEL}' on {device}")
            _whisper_model = WhisperModel(WHISPER_MODEL, device=device, compute_type=compute_type)
            logger.info("Whisper model loaded")
        except ImportError:
            try:
                from faster_whisper import WhisperModel
                logger.info(f"Loading Whisper model '{WHISPER_MODEL}' on cpu (no torch)")
                _whisper_model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8")
            except Exception as e:
                logger.error(f"Failed to load Whisper: {e}")
                _whisper_model = None
        except Exception as e:
            logger.error(f"Failed to load Whisper: {e}")
            _whisper_model = None
    return _whisper_model


def get_groq_client():
    global _groq_client
    if _groq_client is None and GROQ_API_KEY:
        try:
            from groq import Groq
            _groq_client = Groq(api_key=GROQ_API_KEY)
            logger.info("Groq client initialized")
        except Exception as e:
            logger.error(f"Failed to init Groq: {e}")
    return _groq_client


# ---------------------------------------------------------------------------
# System prompt builder
# ---------------------------------------------------------------------------
def build_system_prompt(context: dict, custom_prompt: Optional[str] = None) -> str:
    if custom_prompt:
        return custom_prompt

    facts = context.get("facts", [])
    rules = context.get("rules", [])
    recent_memories = context.get("recent_memories", [])
    local_time = context.get("local_time", "")

    facts_text = ""
    if facts:
        facts_lines = [f"  - {f.get('key', '')}: {f.get('value', '')}" for f in facts[:20]]
        facts_text = "Was du über den Nutzer weißt:\n" + "\n".join(facts_lines)

    rules_text = ""
    if rules:
        rules_lines = [f"  - {r.get('description', '') or r.get('action', '')}" for r in rules]
        rules_text = (
            "Dauerhafte Anweisungen des Nutzers, die du IMMER befolgst:\n" + "\n".join(rules_lines)
        )

    memories_text = ""
    if recent_memories:
        mem_lines = []
        for m in recent_memories[:5]:
            user_msg = m.get("user_message", m.get("document", ""))[:200]
            asst_msg = m.get("assistant_message", "")[:200]
            if user_msg:
                mem_lines.append(f"  Nutzer: {user_msg}")
            if asst_msg:
                mem_lines.append(f"  Jarvis: {asst_msg}")
        if mem_lines:
            memories_text = "Relevante frühere Gespräche:\n" + "\n".join(mem_lines)

    if not local_time:
        local_time = datetime.now().strftime("%A, %d.%m.%Y %H:%M")

    system = f"""Du bist Jarvis, der persönliche KI-Assistent des Nutzers — wie ein hochintelligenter, motivierender Partner, der sich an alles erinnert und dem Nutzer hilft, seine Ziele zu erreichen.

Aktuelles Datum und Uhrzeit: {local_time}

WICHTIGSTE REGEL: Antworte AUSSCHLIESSLICH auf Deutsch. Niemals auf Englisch, egal in welcher Sprache die Frage gestellt wird.

Deine Persönlichkeit und dein Verhalten:
- Intelligent, warmherzig und proaktiv, aber nie aufdringlich
- Du gehst direkt auf das ein, was der Nutzer gerade schreibt — du beginnst NICHT jede Nachricht mit einer Begrüßung
- Begrüße nur dann, wenn es das erste Gespräch ist oder der Nutzer dich begrüßt
- Frage NICHT von dir aus nach Schlaf, Träumen o.ä., außer der Nutzer hat dich per dauerhafter Anweisung (siehe unten) ausdrücklich darum gebeten
- Du motivierst und ermutigst ehrlich, ohne zu schmeicheln
- Du hilfst bei Notizen, Zielen, Finanzen, Planung und allem Persönlichen

WICHTIG für deine Antworten:
- Beziehe dich IMMER auf den bisherigen Gesprächsverlauf (die vorherigen Nachrichten). Erkenne Zusammenhänge und beziehe dich auf das, was gerade gesagt wurde.
- Antworte PRÄZISE und auf den Punkt. Kurze, klare Antworten (1-4 Sätze), außer der Nutzer will ausdrücklich mehr Details.
- Da deine Antworten oft vorgelesen werden: sprich natürlich, ohne Aufzählungszeichen, Sternchen oder Markdown. Schreibe in fließenden Sätzen.
- Keine leeren Floskeln, kein Wiederholen der Frage. Geh direkt zur Sache.

{facts_text}

{rules_text}

{memories_text}

Sei immer hilfreich, ehrlich und persönlich. Wenn du relevanten früheren Kontext kennst, beziehe dich natürlich darauf. Denk daran: immer auf Deutsch."""

    # Clean up extra blank lines
    lines = [line for line in system.split("\n")]
    cleaned = []
    prev_blank = False
    for line in lines:
        if line.strip() == "":
            if not prev_blank:
                cleaned.append(line)
            prev_blank = True
        else:
            cleaned.append(line)
            prev_blank = False

    return "\n".join(cleaned).strip()


# ---------------------------------------------------------------------------
# LLM backends
# ---------------------------------------------------------------------------
async def chat_ollama(messages: list, model: str = None) -> Optional[str]:
    """Try Ollama local LLM. Returns text or None on failure."""
    model = model or OLLAMA_MODEL
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{OLLAMA_URL}/api/chat",
                json={
                    "model": model,
                    "messages": messages,
                    "stream": False,
                    "options": {"temperature": 0.5, "num_predict": 700},
                },
            )
            if resp.status_code == 200:
                data = resp.json()
                return data.get("message", {}).get("content", "")
    except Exception as e:
        logger.warning(f"Ollama failed: {e}")
    return None


def chat_groq(messages: list) -> Optional[str]:
    """Try Groq API. Returns text or None on failure."""
    client = get_groq_client()
    if not client:
        return None
    try:
        completion = client.chat.completions.create(
            model=GROQ_MODEL,
            messages=messages,
            temperature=0.5,
            max_tokens=700,
        )
        return completion.choices[0].message.content
    except Exception as e:
        logger.warning(f"Groq failed: {e}")
        return None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.post("/chat")
async def chat(request: dict):
    """
    Request: {message: str, context: dict, system_prompt: str optional}
    Returns: {response: str, model_used: str, latency_ms: int}
    """
    message = request.get("message", "")
    context = request.get("context", {})
    custom_prompt = request.get("system_prompt")
    history = request.get("history", [])

    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    system_prompt = build_system_prompt(context, custom_prompt)

    # Build the message list WITH recent conversation history so Jarvis
    # remembers the immediate context of the conversation.
    messages = [{"role": "system", "content": system_prompt}]
    if isinstance(history, list):
        for turn in history[-12:]:
            role = turn.get("role")
            content = (turn.get("content") or "").strip()
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": message})

    start_ms = int(time.time() * 1000)
    response_text = None
    model_used = "unknown"

    # Prefer Groq when a key is configured (fast + smart 70B), else use local Ollama.
    # Whichever is primary, the other serves as automatic fallback.
    prefer_groq = bool(GROQ_API_KEY)

    if prefer_groq:
        response_text = chat_groq(messages)
        if response_text:
            model_used = f"groq/{GROQ_MODEL}"
        if not response_text:
            try:
                response_text = await chat_ollama(messages)
                if response_text:
                    model_used = f"ollama/{OLLAMA_MODEL}"
            except Exception as e:
                logger.warning(f"Ollama fallback failed: {e}")
    else:
        try:
            response_text = await chat_ollama(messages)
            if response_text:
                model_used = f"ollama/{OLLAMA_MODEL}"
        except Exception as e:
            logger.warning(f"Ollama attempt failed: {e}")
        if not response_text:
            response_text = chat_groq(messages)
            if response_text:
                model_used = f"groq/{GROQ_MODEL}"

    if not response_text:
        response_text = (
            "Entschuldige, ich kann meine KI gerade nicht erreichen. "
            "Bitte stelle sicher, dass Ollama läuft oder ein GROQ_API_KEY konfiguriert ist."
        )
        model_used = "fallback/static"

    latency_ms = int(time.time() * 1000) - start_ms

    return {
        "response": response_text,
        "model_used": model_used,
        "latency_ms": latency_ms,
    }


@app.post("/voice/stt")
async def voice_stt(audio: UploadFile = File(...)):
    """
    Speech-to-text using faster-whisper.
    Returns: {text: str, language: str, duration_ms: int}
    """
    model = get_whisper_model()
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Whisper model not available. Install faster-whisper and ensure model is downloaded.",
        )

    audio_bytes = await audio.read()
    start_ms = int(time.time() * 1000)

    # Write to temp file (faster-whisper needs a file path)
    suffix = ".wav"
    if audio.filename:
        ext = os.path.splitext(audio.filename)[-1].lower()
        if ext in (".mp3", ".ogg", ".m4a", ".webm", ".wav", ".flac"):
            suffix = ext

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        segments, info = model.transcribe(tmp_path, beam_size=5)
        text_parts = [segment.text for segment in segments]
        text = " ".join(text_parts).strip()
        language = info.language
    except Exception as e:
        logger.error(f"Whisper transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    duration_ms = int(time.time() * 1000) - start_ms
    return {"text": text, "language": language, "duration_ms": duration_ms}


TTS_VOICE = os.getenv("TTS_VOICE", "de-DE-ConradNeural")


@app.post("/voice/tts")
async def voice_tts(request: dict):
    """
    Text-to-speech using Microsoft Edge neural voices (edge-tts).
    Free, no API key, natural-sounding German voice.
    Request: {text: str, speed: float, voice: str optional}
    Returns: audio/mpeg bytes OR JSON fallback if edge-tts is unavailable.
    """
    text = (request.get("text") or "").strip()
    speed = float(request.get("speed", 1.0))
    voice = request.get("voice") or TTS_VOICE

    if not text:
        raise HTTPException(status_code=400, detail="text is required")

    # Convert speed multiplier to edge-tts rate string, e.g. 1.1 -> "+10%"
    pct = int(round((speed - 1.0) * 100))
    rate = f"+{pct}%" if pct >= 0 else f"{pct}%"

    try:
        import edge_tts

        communicate = edge_tts.Communicate(text, voice=voice, rate=rate)
        audio = bytearray()
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio.extend(chunk["data"])

        if not audio:
            raise RuntimeError("edge-tts returned no audio")

        return Response(content=bytes(audio), media_type="audio/mpeg")

    except Exception as e:
        logger.error(f"edge-tts failed: {e}")
        return JSONResponse(
            content={
                "audio": None,
                "error": str(e),
                "fallback": "use_device_tts",
                "message": "Edge-TTS not available (needs internet). Falling back to device TTS.",
            }
        )


@app.post("/extract")
async def extract(request: dict):
    """
    Extract structured info from a user message using LLM.
    Returns: {type: "rule"|"fact"|"data"|"chat", category: str, extracted: dict, confidence: float}
    """
    message = request.get("message", "")
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    extraction_prompt = """You are an information extraction system. Analyze the user message and extract structured information.

Classify the message as ONE of these types:
- "rule": A behavioral instruction (e.g., "always greet me in the morning", "remind me every Monday")
- "fact": A personal fact about the user (e.g., "my brother is Max", "I live in Berlin", "I'm 28 years old")
- "data": A data entry (e.g., "I spent 50€ on food", "I ran 5km today", "I slept 7 hours")
- "chat": Regular conversation (no structured data to extract)

For "fact" type, extract: {key: string, value: string}
For "rule" type, extract: {trigger: string, action: string, description: string}
For "data" type, extract: {category: string, amount: any, unit: string, description: string}
For "chat" type, extract: {}

Category options: "personal", "finance", "sport", "health", "goals", "calendar", "notes", "general"

RESPOND ONLY WITH VALID JSON, no explanation:
{
  "type": "fact|rule|data|chat",
  "category": "...",
  "extracted": {...},
  "confidence": 0.0-1.0
}"""

    messages = [
        {"role": "system", "content": extraction_prompt},
        {"role": "user", "content": message},
    ]

    response_text = None

    # Try Ollama
    try:
        response_text = await chat_ollama(messages)
    except Exception:
        pass

    # Fallback Groq
    if not response_text:
        response_text = chat_groq(messages)

    if not response_text:
        return {
            "type": "chat",
            "category": "general",
            "extracted": {},
            "confidence": 0.0,
        }

    # Parse JSON from LLM response
    try:
        # Strip markdown code blocks if present
        text = response_text.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            text = "\n".join(lines[1:-1]) if lines[-1].strip() == "```" else "\n".join(lines[1:])
        result = json.loads(text)
        # Validate required fields
        result.setdefault("type", "chat")
        result.setdefault("category", "general")
        result.setdefault("extracted", {})
        result.setdefault("confidence", 0.5)
        return result
    except (json.JSONDecodeError, Exception) as e:
        logger.warning(f"Failed to parse extraction result: {e}\nRaw: {response_text[:200]}")
        return {
            "type": "chat",
            "category": "general",
            "extracted": {},
            "confidence": 0.0,
        }


@app.get("/health")
async def health():
    """Check availability of Ollama, Groq, and Whisper."""
    ollama_ok = False
    groq_ok = False
    whisper_ok = False

    # Check Ollama
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{OLLAMA_URL}/api/tags")
            ollama_ok = resp.status_code == 200
    except Exception:
        pass

    # Check Groq
    groq_ok = bool(GROQ_API_KEY and get_groq_client() is not None)

    # Check Whisper (just check if module is importable without loading)
    try:
        import faster_whisper  # noqa: F401
        whisper_ok = True
    except ImportError:
        whisper_ok = False

    return {
        "status": "ok",
        "ollama": ollama_ok,
        "groq": groq_ok,
        "whisper": whisper_ok,
        "ollama_model": OLLAMA_MODEL,
        "whisper_model": WHISPER_MODEL,
    }


@app.get("/")
async def root():
    return {"service": "Jarvis AI Engine", "version": "1.0.0", "status": "running"}
