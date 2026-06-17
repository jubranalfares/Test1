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
WHISPER_MODEL = os.getenv("WHISPER_MODEL", "base")

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
    is_morning = context.get("is_morning", False)
    briefing = context.get("briefing", "")

    facts_text = ""
    if facts:
        facts_lines = [f"  - {f.get('key', '')}: {f.get('value', '')}" for f in facts[:20]]
        facts_text = "Known facts about the user:\n" + "\n".join(facts_lines)

    rules_text = ""
    if rules:
        rules_lines = [f"  - [{r.get('trigger', '')}] → {r.get('description', r.get('action', ''))}" for r in rules]
        rules_text = "Behavior rules to follow:\n" + "\n".join(rules_lines)

    memories_text = ""
    if recent_memories:
        mem_lines = []
        for m in recent_memories[:5]:
            user_msg = m.get("user_message", m.get("document", ""))[:200]
            asst_msg = m.get("assistant_message", "")[:200]
            if user_msg:
                mem_lines.append(f"  User: {user_msg}")
            if asst_msg:
                mem_lines.append(f"  Jarvis: {asst_msg}")
        if mem_lines:
            memories_text = "Recent conversation snippets:\n" + "\n".join(mem_lines)

    morning_text = ""
    if is_morning:
        morning_text = (
            "It is morning time. Greet the user warmly, ask how they slept if not already done today.\n"
        )
        if briefing:
            morning_text += f"Today's briefing: {briefing}\n"

    now = datetime.now()
    date_str = now.strftime("%A, %B %d, %Y %H:%M")

    system = f"""You are Jarvis, an intelligent personal AI assistant. You are like a brilliant, motivating partner who remembers everything about the user and helps them achieve their goals.

Current date and time: {date_str}

Your personality:
- Intelligent, warm, and proactive
- You remember past conversations and reference them naturally
- You motivate and encourage without being sycophantic
- You are direct and concise unless detail is requested
- You speak in the user's language naturally
- You help with notes, goals, finance tracking, planning, and anything personal

{facts_text}

{rules_text}

{memories_text}

{morning_text}

Always be helpful, honest, and personalized. If you recall relevant past context, reference it naturally."""

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
                    "options": {"temperature": 0.7, "num_predict": 1024},
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
            model="llama-3.1-8b-instant",
            messages=messages,
            temperature=0.7,
            max_tokens=1024,
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

    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    system_prompt = build_system_prompt(context, custom_prompt)

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": message},
    ]

    start_ms = int(time.time() * 1000)
    response_text = None
    model_used = "unknown"

    # Try Ollama first
    try:
        response_text = await chat_ollama(messages)
        if response_text:
            model_used = f"ollama/{OLLAMA_MODEL}"
    except Exception as e:
        logger.warning(f"Ollama attempt failed: {e}")

    # Fallback to Groq
    if not response_text:
        response_text = chat_groq(messages)
        if response_text:
            model_used = "groq/llama-3.1-8b-instant"

    if not response_text:
        response_text = (
            "I'm sorry, I'm having trouble connecting to my AI backend right now. "
            "Please ensure Ollama is running or configure a GROQ_API_KEY."
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


@app.post("/voice/tts")
async def voice_tts(request: dict):
    """
    Text-to-speech using piper-tts subprocess.
    Request: {text: str, speed: float}
    Returns: audio/wav bytes OR JSON error if piper not available.
    """
    text = request.get("text", "")
    speed = float(request.get("speed", 1.0))

    if not text:
        raise HTTPException(status_code=400, detail="text is required")

    # Check if piper is available
    piper_path = shutil.which("piper") or shutil.which("piper-tts")
    if piper_path is None:
        # Check common install locations
        for candidate in ["/usr/local/bin/piper", "/usr/bin/piper", "/app/piper"]:
            if os.path.isfile(candidate):
                piper_path = candidate
                break

    if piper_path is None:
        return JSONResponse(
            content={
                "audio": None,
                "error": "piper_not_installed",
                "fallback": "use_device_tts",
                "message": "Piper TTS binary not found. Install piper-tts or use device TTS.",
            }
        )

    # Determine voice model
    models_dir = os.getenv("PIPER_MODELS_DIR", "/app/models/piper")
    lang = os.getenv("TTS_LANGUAGE", "en")
    if lang.startswith("de"):
        voice_model = os.path.join(models_dir, "de_DE-thorsten-high.onnx")
        voice_config = os.path.join(models_dir, "de_DE-thorsten-high.onnx.json")
    else:
        voice_model = os.path.join(models_dir, "en_US-ryan-high.onnx")
        voice_config = os.path.join(models_dir, "en_US-ryan-high.onnx.json")

    # Fallback: use any available model
    if not os.path.isfile(voice_model):
        # Try to find any .onnx file in models dir
        if os.path.isdir(models_dir):
            for fname in os.listdir(models_dir):
                if fname.endswith(".onnx") and not fname.endswith(".json"):
                    voice_model = os.path.join(models_dir, fname)
                    voice_config = voice_model + ".json"
                    break

    if not os.path.isfile(voice_model):
        return JSONResponse(
            content={
                "audio": None,
                "error": "piper_model_not_found",
                "fallback": "use_device_tts",
                "message": f"Piper voice model not found at {voice_model}. Download a voice model.",
            }
        )

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as out_tmp:
        out_path = out_tmp.name

    try:
        cmd = [
            piper_path,
            "--model", voice_model,
            "--output_file", out_path,
            "--length_scale", str(1.0 / speed),
        ]
        if os.path.isfile(voice_config):
            cmd += ["--config", voice_config]

        proc = subprocess.run(
            cmd,
            input=text.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )

        if proc.returncode != 0:
            stderr = proc.stderr.decode("utf-8", errors="replace")
            logger.error(f"Piper failed: {stderr}")
            return JSONResponse(
                content={
                    "audio": None,
                    "error": "piper_failed",
                    "fallback": "use_device_tts",
                    "detail": stderr[:500],
                }
            )

        with open(out_path, "rb") as f:
            audio_bytes = f.read()

        return Response(content=audio_bytes, media_type="audio/wav")

    except subprocess.TimeoutExpired:
        return JSONResponse(
            content={"audio": None, "error": "piper_timeout", "fallback": "use_device_tts"}
        )
    except Exception as e:
        logger.error(f"TTS error: {e}")
        return JSONResponse(
            content={"audio": None, "error": str(e), "fallback": "use_device_tts"}
        )
    finally:
        try:
            os.unlink(out_path)
        except Exception:
            pass


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
