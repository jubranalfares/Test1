"""
Jarvis API Gateway - Port 8000
Entry point for the Flutter app. Handles JWT auth and proxies requests to microservices.
"""

import os
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Optional, AsyncGenerator

import httpx
from fastapi import (
    FastAPI, Depends, HTTPException, status, UploadFile, File,
    Request, Response, WebSocket, WebSocketDisconnect, Form
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SECRET_KEY = os.getenv("SECRET_KEY", "jarvis-secret-2024")
USER_PASSWORD = os.getenv("USER_PASSWORD", "jarvis2024")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 30  # 30 days

AI_ENGINE_URL = os.getenv("AI_ENGINE_URL", "http://localhost:8001")
MEMORY_ENGINE_URL = os.getenv("MEMORY_ENGINE_URL", "http://localhost:8002")
NOTES_SERVICE_URL = os.getenv("NOTES_SERVICE_URL", "http://localhost:8003")
GOALS_SERVICE_URL = os.getenv("GOALS_SERVICE_URL", "http://localhost:8004")
FINANCE_SERVICE_URL = os.getenv("FINANCE_SERVICE_URL", "http://localhost:8005")
SPORT_SERVICE_URL = os.getenv("SPORT_SERVICE_URL", "http://localhost:8006")
CALENDAR_SERVICE_URL = os.getenv("CALENDAR_SERVICE_URL", "http://localhost:8007")

JARVIS_USERNAME = "jarvis"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api-gateway")

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis API Gateway", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> str:
    """Verify JWT and return username, raise HTTPException on failure."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        return username
    except JWTError:
        raise credentials_exception


async def get_current_user(token: str = Depends(oauth2_scheme)) -> str:
    return verify_token(token)


# ---------------------------------------------------------------------------
# HTTP client factory
# ---------------------------------------------------------------------------
def get_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=60.0)


# ---------------------------------------------------------------------------
# Auth endpoints
# ---------------------------------------------------------------------------
@app.post("/token")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """Issue a JWT token for valid credentials."""
    if form_data.username != JARVIS_USERNAME or form_data.password != USER_PASSWORD:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = create_access_token({"sub": form_data.username})
    return {"access_token": token, "token_type": "bearer"}


# ---------------------------------------------------------------------------
# Chat endpoint
# ---------------------------------------------------------------------------
@app.post("/chat")
async def chat(
    request: Request,
    current_user: str = Depends(get_current_user),
):
    """
    1. Parse message from body
    2. Fetch context from memory-engine
    3. Call ai-engine with context
    4. Store result back in memory-engine
    5. Return AI response
    """
    body = await request.json()
    message = body.get("message", "")
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    async with get_client() as client:
        # Step 1: Get context from memory-engine
        context = {}
        try:
            ctx_resp = await client.post(
                f"{MEMORY_ENGINE_URL}/context",
                json={"query": message},
            )
            if ctx_resp.status_code == 200:
                context = ctx_resp.json()
        except Exception as e:
            logger.warning(f"memory-engine context fetch failed: {e}")

        # Step 2: Call ai-engine
        ai_payload = {
            "message": message,
            "context": context,
            "system_prompt": body.get("system_prompt"),
        }
        try:
            ai_resp = await client.post(f"{AI_ENGINE_URL}/chat", json=ai_payload)
            ai_resp.raise_for_status()
            ai_data = ai_resp.json()
        except Exception as e:
            logger.error(f"ai-engine chat failed: {e}")
            raise HTTPException(status_code=502, detail=f"AI engine error: {str(e)}")

        # Step 3: Store in memory-engine
        try:
            await client.post(
                f"{MEMORY_ENGINE_URL}/remember",
                json={
                    "user_message": message,
                    "assistant_message": ai_data.get("response", ""),
                    "timestamp": datetime.utcnow().isoformat(),
                },
            )
        except Exception as e:
            logger.warning(f"memory-engine remember failed: {e}")

        return ai_data


# ---------------------------------------------------------------------------
# Voice endpoints
# ---------------------------------------------------------------------------
@app.post("/voice/stt")
async def voice_stt(
    audio: UploadFile = File(...),
    current_user: str = Depends(get_current_user),
):
    """Proxy audio file to ai-engine for speech-to-text."""
    audio_bytes = await audio.read()
    async with get_client() as client:
        try:
            files = {"audio": (audio.filename, audio_bytes, audio.content_type or "audio/wav")}
            resp = await client.post(f"{AI_ENGINE_URL}/voice/stt", files=files)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            logger.error(f"STT proxy failed: {e}")
            raise HTTPException(status_code=502, detail=str(e))


@app.post("/voice/tts")
async def voice_tts(
    request: Request,
    current_user: str = Depends(get_current_user),
):
    """Proxy TTS request to ai-engine, return audio bytes or JSON error."""
    body = await request.json()
    async with get_client() as client:
        try:
            resp = await client.post(f"{AI_ENGINE_URL}/voice/tts", json=body)
            content_type = resp.headers.get("content-type", "application/json")
            if "audio" in content_type:
                return Response(content=resp.content, media_type=content_type)
            return resp.json()
        except Exception as e:
            logger.error(f"TTS proxy failed: {e}")
            raise HTTPException(status_code=502, detail=str(e))


# ---------------------------------------------------------------------------
# Notes proxy  (all methods, all sub-paths)
# ---------------------------------------------------------------------------
async def _proxy(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    request: Request,
    path_suffix: str = "",
    params: dict = None,
    body=None,
):
    """Generic proxy helper."""
    target = url + path_suffix
    query = str(request.url.query)
    if query:
        target += f"?{query}"
    headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}
    try:
        if body is not None:
            resp = await client.request(method, target, json=body, headers=headers)
        else:
            raw = await request.body()
            resp = await client.request(method, target, content=raw, headers=headers)
        return Response(
            content=resp.content,
            status_code=resp.status_code,
            media_type=resp.headers.get("content-type", "application/json"),
        )
    except Exception as e:
        logger.error(f"Proxy {method} {target} failed: {e}")
        raise HTTPException(status_code=502, detail=str(e))


@app.api_route("/notes/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def notes_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, NOTES_SERVICE_URL, request, f"/notes/{path}")


@app.api_route("/notes", methods=["GET", "POST"])
async def notes_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, NOTES_SERVICE_URL, request, "/notes")


# ---------------------------------------------------------------------------
# Goals proxy  (-> goals-service)
# ---------------------------------------------------------------------------
@app.api_route("/goals/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def goals_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, GOALS_SERVICE_URL, request, f"/goals/{path}")


@app.api_route("/goals", methods=["GET", "POST"])
async def goals_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, GOALS_SERVICE_URL, request, "/goals")


# ---------------------------------------------------------------------------
# Finance proxy  (-> finance-service: /finance + /transactions)
# ---------------------------------------------------------------------------
@app.api_route("/finance/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def finance_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, FINANCE_SERVICE_URL, request, f"/finance/{path}")


@app.api_route("/finance", methods=["GET", "POST"])
async def finance_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, FINANCE_SERVICE_URL, request, "/finance")


@app.api_route("/transactions/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def transactions_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, FINANCE_SERVICE_URL, request, f"/transactions/{path}")


@app.api_route("/transactions", methods=["GET", "POST"])
async def transactions_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, FINANCE_SERVICE_URL, request, "/transactions")


# ---------------------------------------------------------------------------
# Sport proxy  (-> sport-service: /sport + /workouts)
# ---------------------------------------------------------------------------
@app.api_route("/sport/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def sport_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, SPORT_SERVICE_URL, request, f"/sport/{path}")


@app.api_route("/sport", methods=["GET", "POST"])
async def sport_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, SPORT_SERVICE_URL, request, "/sport")


@app.api_route("/workouts/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def workouts_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, SPORT_SERVICE_URL, request, f"/workouts/{path}")


@app.api_route("/workouts", methods=["GET", "POST"])
async def workouts_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, SPORT_SERVICE_URL, request, "/workouts")


# ---------------------------------------------------------------------------
# Calendar proxy  (-> calendar-service: /events)
# ---------------------------------------------------------------------------
@app.api_route("/events/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def events_proxy(path: str, request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, CALENDAR_SERVICE_URL, request, f"/events/{path}")


@app.api_route("/events", methods=["GET", "POST"])
async def events_proxy_root(request: Request, current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        return await _proxy(client, request.method, CALENDAR_SERVICE_URL, request, "/events")


# ---------------------------------------------------------------------------
# Memory endpoints
# ---------------------------------------------------------------------------
@app.get("/memory/facts")
async def memory_facts(current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        try:
            resp = await client.get(f"{MEMORY_ENGINE_URL}/facts")
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))


@app.post("/memory/rule")
async def memory_add_rule(request: Request, current_user: str = Depends(get_current_user)):
    body = await request.json()
    async with get_client() as client:
        try:
            resp = await client.post(f"{MEMORY_ENGINE_URL}/rule", json=body)
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))


@app.get("/memory/briefing")
async def memory_briefing(current_user: str = Depends(get_current_user)):
    async with get_client() as client:
        try:
            resp = await client.get(f"{MEMORY_ENGINE_URL}/briefing")
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))


@app.get("/memory/opening")
async def memory_opening(current_user: str = Depends(get_current_user)):
    """Proactive opening message for when the app is opened."""
    async with get_client() as client:
        try:
            resp = await client.get(f"{MEMORY_ENGINE_URL}/opening")
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    """Check all downstream services and return their status."""
    services = {
        "ai-engine": f"{AI_ENGINE_URL}/health",
        "memory-engine": f"{MEMORY_ENGINE_URL}/health",
        "notes-service": f"{NOTES_SERVICE_URL}/health",
        "goals-service": f"{GOALS_SERVICE_URL}/health",
        "finance-service": f"{FINANCE_SERVICE_URL}/health",
        "sport-service": f"{SPORT_SERVICE_URL}/health",
        "calendar-service": f"{CALENDAR_SERVICE_URL}/health",
    }
    results = {"gateway": "ok", "services": {}}

    async with get_client() as client:
        for name, url in services.items():
            try:
                resp = await client.get(url)
                if resp.status_code == 200:
                    results["services"][name] = {"status": "ok", "detail": resp.json()}
                else:
                    results["services"][name] = {"status": "degraded", "code": resp.status_code}
            except Exception as e:
                results["services"][name] = {"status": "unreachable", "error": str(e)}

    all_ok = all(s["status"] == "ok" for s in results["services"].values())
    results["overall"] = "ok" if all_ok else "degraded"
    return results


# ---------------------------------------------------------------------------
# WebSocket streaming chat
# ---------------------------------------------------------------------------
@app.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket):
    """
    Real-time streaming chat over WebSocket.
    Protocol:
      Client → {"token": "<jwt>", "message": "<text>"}
      Server → {"type": "token", "content": "..."} (streaming chunks)
              {"type": "done", "model_used": "...", "latency_ms": ...}
              {"type": "error", "detail": "..."}
    """
    await websocket.accept()
    try:
        # First message must contain auth token
        auth_msg = await websocket.receive_json()
        token = auth_msg.get("token")
        if not token:
            await websocket.send_json({"type": "error", "detail": "token required"})
            await websocket.close(code=4001)
            return

        try:
            username = verify_token(token)
        except HTTPException:
            await websocket.send_json({"type": "error", "detail": "invalid token"})
            await websocket.close(code=4001)
            return

        message = auth_msg.get("message", "")
        if not message:
            await websocket.send_json({"type": "error", "detail": "message required"})
            return

        async with get_client() as client:
            # Get context
            context = {}
            try:
                ctx_resp = await client.post(
                    f"{MEMORY_ENGINE_URL}/context",
                    json={"query": message},
                )
                if ctx_resp.status_code == 200:
                    context = ctx_resp.json()
            except Exception as e:
                logger.warning(f"WS context fetch failed: {e}")

            # Call ai-engine (non-streaming for now; ai-engine can be extended)
            ai_payload = {"message": message, "context": context}
            try:
                ai_resp = await client.post(f"{AI_ENGINE_URL}/chat", json=ai_payload)
                ai_resp.raise_for_status()
                ai_data = ai_resp.json()
            except Exception as e:
                await websocket.send_json({"type": "error", "detail": str(e)})
                return

            # Simulate streaming by sending the response word by word
            response_text = ai_data.get("response", "")
            words = response_text.split(" ")
            for i, word in enumerate(words):
                chunk = word if i == 0 else " " + word
                await websocket.send_json({"type": "token", "content": chunk})
                await asyncio.sleep(0.02)

            await websocket.send_json({
                "type": "done",
                "model_used": ai_data.get("model_used", "unknown"),
                "latency_ms": ai_data.get("latency_ms", 0),
            })

            # Store in memory
            try:
                await client.post(
                    f"{MEMORY_ENGINE_URL}/remember",
                    json={
                        "user_message": message,
                        "assistant_message": response_text,
                        "timestamp": datetime.utcnow().isoformat(),
                    },
                )
            except Exception as e:
                logger.warning(f"WS memory store failed: {e}")

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.send_json({"type": "error", "detail": str(e)})
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Root
# ---------------------------------------------------------------------------
@app.get("/")
async def root():
    return {"service": "Jarvis API Gateway", "version": "1.0.0", "status": "running"}
