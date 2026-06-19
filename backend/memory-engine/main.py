"""
Jarvis Memory Engine - Port 8002
The brain/memory of Jarvis. Uses SQLite for structured data and ChromaDB for semantic search.
"""

import os
import json
import logging
import sqlite3
import threading
import time
import uuid
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any
from contextlib import contextmanager

import httpx
from fastapi import FastAPI, HTTPException
from dotenv import load_dotenv
from apscheduler.schedulers.asyncio import AsyncIOScheduler

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AI_ENGINE_URL = os.getenv("AI_ENGINE_URL", "http://localhost:8001")
DB_PATH = os.getenv("DB_PATH", "/app/data/memory.db")
CHROMA_PATH = os.getenv("CHROMA_PATH", "/app/chroma")
TIMEZONE = os.getenv("TIMEZONE", "Europe/Berlin")

# German weekday names for nice briefings
_WEEKDAYS_DE = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]


def local_now() -> datetime:
    """Current time in the user's timezone (default Europe/Berlin), not UTC."""
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo(TIMEZONE))
    except Exception:
        return datetime.now()


def local_datetime_str() -> str:
    """Human-friendly German date/time string in the user's timezone."""
    n = local_now()
    return f"{_WEEKDAYS_DE[n.weekday()]}, {n.strftime('%d.%m.%Y %H:%M')}"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("memory-engine")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Memory Engine", version="1.0.0")

# ---------------------------------------------------------------------------
# SQLite setup with thread-safe connection pool
# ---------------------------------------------------------------------------
_db_lock = threading.Lock()


def get_db_connection() -> sqlite3.Connection:
    """Create a new SQLite connection (check_same_thread=False for use with thread lock)."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


@contextmanager
def db_cursor():
    """Context manager that provides a DB cursor with lock and auto-commit."""
    with _db_lock:
        conn = get_db_connection()
        try:
            cur = conn.cursor()
            yield cur
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


def init_db():
    """Create tables if they don't exist."""
    with db_cursor() as cur:
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS facts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT NOT NULL UNIQUE,
                value TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                confidence REAL DEFAULT 1.0
            );

            CREATE TABLE IF NOT EXISTS behavior_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trigger TEXT NOT NULL,
                action TEXT NOT NULL,
                active INTEGER DEFAULT 1,
                created_at TEXT NOT NULL,
                description TEXT DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_message TEXT NOT NULL,
                assistant_message TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                summary TEXT DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS daily_summaries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL UNIQUE,
                summary_text TEXT NOT NULL,
                key_insights TEXT DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_conversations_timestamp
                ON conversations(timestamp);
            CREATE INDEX IF NOT EXISTS idx_facts_key ON facts(key);
        """)
    logger.info("Database initialized")


# ---------------------------------------------------------------------------
# ChromaDB setup
# ---------------------------------------------------------------------------
_chroma_client = None
_chroma_collection = None
_embedding_fn = None
_chroma_lock = threading.Lock()


def get_chroma():
    """Lazy-initialize ChromaDB client and collection."""
    global _chroma_client, _chroma_collection, _embedding_fn
    with _chroma_lock:
        if _chroma_collection is not None:
            return _chroma_collection
        try:
            import chromadb
            from chromadb.utils import embedding_functions

            os.makedirs(CHROMA_PATH, exist_ok=True)
            _chroma_client = chromadb.PersistentClient(path=CHROMA_PATH)

            # Use sentence-transformers for embeddings
            _embedding_fn = embedding_functions.SentenceTransformerEmbeddingFunction(
                model_name="all-MiniLM-L6-v2"
            )

            _chroma_collection = _chroma_client.get_or_create_collection(
                name="memories",
                embedding_function=_embedding_fn,
                metadata={"hnsw:space": "cosine"},
            )
            logger.info(f"ChromaDB initialized, {_chroma_collection.count()} memories stored")
            return _chroma_collection
        except Exception as e:
            logger.error(f"ChromaDB initialization failed: {e}")
            return None


def chroma_add(memory_id: str, user_message: str, assistant_message: str, timestamp: str):
    """Add a conversation to ChromaDB."""
    collection = get_chroma()
    if collection is None:
        return
    try:
        combined = f"User: {user_message}\nJarvis: {assistant_message}"
        collection.add(
            ids=[memory_id],
            documents=[combined],
            metadatas=[{
                "user_message": user_message[:500],
                "assistant_message": assistant_message[:500],
                "timestamp": timestamp,
            }],
        )
    except Exception as e:
        logger.warning(f"ChromaDB add failed: {e}")


def chroma_search(query: str, n_results: int = 5) -> List[Dict]:
    """Semantic search in ChromaDB."""
    collection = get_chroma()
    if collection is None or collection.count() == 0:
        return []
    try:
        results = collection.query(
            query_texts=[query],
            n_results=min(n_results, collection.count()),
        )
        memories = []
        if results and results.get("metadatas"):
            for i, meta in enumerate(results["metadatas"][0]):
                memories.append({
                    "user_message": meta.get("user_message", ""),
                    "assistant_message": meta.get("assistant_message", ""),
                    "timestamp": meta.get("timestamp", ""),
                    "distance": results["distances"][0][i] if results.get("distances") else 0,
                    "document": results["documents"][0][i] if results.get("documents") else "",
                })
        return memories
    except Exception as e:
        logger.warning(f"ChromaDB search failed: {e}")
        return []


# ---------------------------------------------------------------------------
# Briefing cache
# ---------------------------------------------------------------------------
_briefing_cache: Dict[str, Any] = {"text": "", "generated_at": None}
_briefing_lock = threading.Lock()


def get_briefing_cache() -> Optional[str]:
    with _briefing_lock:
        if _briefing_cache["generated_at"] is None:
            return None
        age = datetime.utcnow() - _briefing_cache["generated_at"]
        if age < timedelta(hours=1):
            return _briefing_cache["text"]
        return None


def set_briefing_cache(text: str):
    with _briefing_lock:
        _briefing_cache["text"] = text
        _briefing_cache["generated_at"] = datetime.utcnow()


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    # Pre-warm ChromaDB in background (might take time to download model)
    import asyncio
    asyncio.get_event_loop().run_in_executor(None, get_chroma)
    logger.info("Memory engine started")

    # Schedule nightly summarization at 2:00 AM
    scheduler = AsyncIOScheduler()
    scheduler.add_job(nightly_summarize, "cron", hour=2, minute=0)
    scheduler.start()


# ---------------------------------------------------------------------------
# Helper: call ai-engine
# ---------------------------------------------------------------------------
async def call_ai_extract(message: str) -> Optional[Dict]:
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(f"{AI_ENGINE_URL}/extract", json={"message": message})
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logger.warning(f"ai-engine /extract call failed: {e}")
    return None


async def call_ai_chat(message: str, context: dict = None, system_prompt: str = None) -> Optional[str]:
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            payload = {"message": message, "context": context or {}}
            if system_prompt:
                payload["system_prompt"] = system_prompt
            resp = await client.post(f"{AI_ENGINE_URL}/chat", json=payload)
            if resp.status_code == 200:
                return resp.json().get("response", "")
    except Exception as e:
        logger.warning(f"ai-engine /chat call failed: {e}")
    return None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.post("/context")
async def get_context(request: dict):
    """
    Build full context for the next AI response.
    Input: {query: str}
    Returns: {facts, rules, recent_memories, is_morning, briefing}
    """
    query = request.get("query", "")

    # Semantic search
    recent_memories = chroma_search(query, n_results=5) if query else []

    # Get facts
    with db_cursor() as cur:
        cur.execute("SELECT key, value, timestamp, confidence FROM facts ORDER BY timestamp DESC LIMIT 20")
        facts = [dict(row) for row in cur.fetchall()]

    # Get active rules
    with db_cursor() as cur:
        cur.execute(
            "SELECT id, trigger, action, description, created_at FROM behavior_rules WHERE active=1"
        )
        rules = [dict(row) for row in cur.fetchall()]

    # Check if morning (6-10 AM) in the user's local timezone
    now = local_now()
    is_morning = 6 <= now.hour < 10

    return {
        "facts": facts,
        "rules": rules,
        "recent_memories": recent_memories,
        "is_morning": is_morning,
        "local_time": local_datetime_str(),
    }


@app.post("/remember")
async def remember(request: dict):
    """
    Store a conversation and extract facts/rules from it.
    Input: {user_message: str, assistant_message: str, timestamp: str}
    """
    user_message = request.get("user_message", "")
    assistant_message = request.get("assistant_message", "")
    timestamp = request.get("timestamp", datetime.utcnow().isoformat())

    if not user_message:
        raise HTTPException(status_code=400, detail="user_message is required")

    # Store in SQLite
    with db_cursor() as cur:
        cur.execute(
            "INSERT INTO conversations (user_message, assistant_message, timestamp) VALUES (?, ?, ?)",
            (user_message, assistant_message, timestamp),
        )

    # Add to ChromaDB
    memory_id = str(uuid.uuid4())
    chroma_add(memory_id, user_message, assistant_message, timestamp)

    # Extract structured info from user message
    extraction = await call_ai_extract(user_message)
    if extraction:
        ex_type = extraction.get("type", "chat")
        extracted = extraction.get("extracted", {})
        confidence = extraction.get("confidence", 0.0)

        if ex_type == "fact" and extracted.get("key") and confidence > 0.5:
            with db_cursor() as cur:
                cur.execute(
                    """INSERT INTO facts (key, value, timestamp, confidence)
                       VALUES (?, ?, ?, ?)
                       ON CONFLICT(key) DO UPDATE SET
                           value=excluded.value,
                           timestamp=excluded.timestamp,
                           confidence=excluded.confidence""",
                    (
                        extracted["key"].lower().strip(),
                        extracted.get("value", ""),
                        timestamp,
                        confidence,
                    ),
                )
            logger.info(f"Stored fact: {extracted['key']} = {extracted.get('value')}")

        elif ex_type == "rule" and extracted.get("trigger") and confidence > 0.5:
            with db_cursor() as cur:
                cur.execute(
                    """INSERT INTO behavior_rules (trigger, action, description, created_at)
                       VALUES (?, ?, ?, ?)""",
                    (
                        extracted.get("trigger", ""),
                        extracted.get("action", ""),
                        extracted.get("description", ""),
                        timestamp,
                    ),
                )
            logger.info(f"Stored rule: {extracted.get('trigger')} → {extracted.get('action')}")

    return {"status": "remembered", "memory_id": memory_id}


@app.get("/facts")
async def get_facts():
    """Return all facts."""
    with db_cursor() as cur:
        cur.execute("SELECT key, value, timestamp, confidence FROM facts ORDER BY timestamp DESC")
        facts = [dict(row) for row in cur.fetchall()]
    return {"facts": facts, "count": len(facts)}


@app.post("/fact")
async def add_fact(request: dict):
    """Add or update a fact. Input: {key: str, value: str, confidence: float}"""
    key = request.get("key", "").lower().strip()
    value = request.get("value", "")
    confidence = float(request.get("confidence", 1.0))

    if not key or not value:
        raise HTTPException(status_code=400, detail="key and value are required")

    timestamp = datetime.utcnow().isoformat()
    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO facts (key, value, timestamp, confidence)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(key) DO UPDATE SET
                   value=excluded.value,
                   timestamp=excluded.timestamp,
                   confidence=excluded.confidence""",
            (key, value, timestamp, confidence),
        )
    return {"status": "ok", "key": key, "value": value}


@app.get("/rules")
async def get_rules():
    """Return all active behavior rules."""
    with db_cursor() as cur:
        cur.execute(
            "SELECT id, trigger, action, description, active, created_at FROM behavior_rules WHERE active=1"
        )
        rules = [dict(row) for row in cur.fetchall()]
    return {"rules": rules, "count": len(rules)}


@app.post("/rule")
async def add_rule(request: dict):
    """Add a behavior rule. Input: {trigger: str, action: str, description: str}"""
    trigger = request.get("trigger", "").strip()
    action = request.get("action", "").strip()
    description = request.get("description", "").strip()

    if not trigger or not action:
        raise HTTPException(status_code=400, detail="trigger and action are required")

    created_at = datetime.utcnow().isoformat()
    with db_cursor() as cur:
        cur.execute(
            "INSERT INTO behavior_rules (trigger, action, description, active, created_at) VALUES (?, ?, ?, 1, ?)",
            (trigger, action, description, created_at),
        )
        rule_id = cur.lastrowid

    return {"status": "ok", "id": rule_id, "trigger": trigger, "action": action}


@app.put("/rule/{rule_id}/toggle")
async def toggle_rule(rule_id: int):
    """Toggle a rule active/inactive."""
    with db_cursor() as cur:
        cur.execute("SELECT id, active FROM behavior_rules WHERE id=?", (rule_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Rule not found")
        new_active = 0 if row["active"] else 1
        cur.execute("UPDATE behavior_rules SET active=? WHERE id=?", (new_active, rule_id))
    return {"status": "ok", "id": rule_id, "active": bool(new_active)}


@app.get("/briefing")
async def get_briefing():
    """
    Generate morning briefing. Cached for 1 hour.
    Returns: {briefing: str, cached: bool, generated_at: str}
    """
    cached = get_briefing_cache()
    if cached:
        return {"briefing": cached, "cached": True}

    # Build briefing context
    with db_cursor() as cur:
        cur.execute("SELECT key, value FROM facts ORDER BY timestamp DESC LIMIT 10")
        facts = [dict(row) for row in cur.fetchall()]

    with db_cursor() as cur:
        cur.execute("SELECT trigger, action, description FROM behavior_rules WHERE active=1")
        rules = [dict(row) for row in cur.fetchall()]

    date_str = local_datetime_str()

    facts_text = "\n".join([f"- {f['key']}: {f['value']}" for f in facts]) if facts else "Noch keine Fakten gespeichert."
    rules_text = "\n".join([f"- {r['description'] or r['action']}" for r in rules]) if rules else "Keine besonderen Anweisungen."

    system_prompt = f"""Du bist Jarvis, der persönliche KI-Assistent des Nutzers. Erstelle ein kurzes, motivierendes Morgen-Briefing.
Heute ist {date_str}.

Was du über den Nutzer weißt:
{facts_text}

Dauerhafte Anweisungen des Nutzers:
{rules_text}

Schreibe ein Briefing aus 3-5 Sätzen. Sei warmherzig, persönlich und motivierend. Beziehe dich auf das, was du über den Nutzer weißt. WICHTIG: Antworte ausschließlich auf Deutsch."""

    briefing_text = await call_ai_chat(
        "Erstelle mein Morgen-Briefing",
        system_prompt=system_prompt,
    )

    if not briefing_text:
        briefing_text = f"Guten Morgen! Heute ist {date_str}. Lass uns einen großartigen, produktiven Tag machen!"

    set_briefing_cache(briefing_text)

    return {
        "briefing": briefing_text,
        "cached": False,
        "generated_at": datetime.utcnow().isoformat(),
    }


@app.get("/opening")
async def get_opening():
    """
    Generate a proactive opening message for when the user opens the app.
    Time-aware (morning/day/evening/night), follows behavior rules, in German.
    Returns: {message: str, local_time: str}
    """
    with db_cursor() as cur:
        cur.execute("SELECT key, value FROM facts ORDER BY timestamp DESC LIMIT 10")
        facts = [dict(row) for row in cur.fetchall()]

    with db_cursor() as cur:
        cur.execute("SELECT trigger, action, description FROM behavior_rules WHERE active=1")
        rules = [dict(row) for row in cur.fetchall()]

    # Most recent conversation for continuity
    with db_cursor() as cur:
        cur.execute(
            "SELECT user_message, assistant_message FROM conversations ORDER BY id DESC LIMIT 3"
        )
        recent = [dict(row) for row in cur.fetchall()]

    n = local_now()
    hour = n.hour
    if 5 <= hour < 11:
        tageszeit = "Morgen"
    elif 11 <= hour < 17:
        tageszeit = "Tag/Mittag"
    elif 17 <= hour < 22:
        tageszeit = "Abend"
    else:
        tageszeit = "Nacht"

    facts_text = "\n".join([f"- {f['key']}: {f['value']}" for f in facts]) if facts else "Noch nichts bekannt."
    rules_text = "\n".join([f"- {r['description'] or r['action']}" for r in rules]) if rules else "Keine besonderen Anweisungen."
    recent_text = ""
    if recent:
        recent_text = "Letzte Gespräche:\n" + "\n".join(
            [f"  Nutzer: {r['user_message'][:120]}" for r in reversed(recent)]
        )

    system_prompt = f"""Du bist Jarvis, der persönliche KI-Assistent des Nutzers. Der Nutzer hat gerade die App geöffnet.
Begrüße ihn von dir aus mit EINER kurzen, natürlichen Eröffnungsnachricht (1-2 Sätze), passend zur Tageszeit ({tageszeit}, {local_datetime_str()}).

Was du über den Nutzer weißt:
{facts_text}

Dauerhafte Anweisungen des Nutzers (diese IMMER befolgen):
{rules_text}

{recent_text}

Regeln:
- Antworte ausschließlich auf Deutsch.
- Sei warmherzig und kurz, kein langes Gerede.
- Befolge die dauerhaften Anweisungen des Nutzers, falls vorhanden (z.B. wenn er morgens nach dem Schlaf gefragt werden möchte).
- Wenn keine besondere Anweisung gilt, begrüße passend zur Tageszeit und frage offen, was ansteht.
- Erfinde keine Termine oder Fakten, die du nicht kennst."""

    message = await call_ai_chat("Öffne das Gespräch", system_prompt=system_prompt)

    if not message:
        greet = {"Morgen": "Guten Morgen", "Tag/Mittag": "Hallo", "Abend": "Guten Abend", "Nacht": "Hallo"}[tageszeit]
        message = f"{greet}! Was steht an? Ich bin bereit. 🚀"

    return {"message": message, "local_time": local_datetime_str()}


@app.post("/summarize")
async def summarize():
    """
    Summarize yesterday's conversations and extract insights.
    Typically called by a nightly job.
    """
    yesterday = (date.today() - timedelta(days=1)).isoformat()

    with db_cursor() as cur:
        cur.execute(
            """SELECT user_message, assistant_message FROM conversations
               WHERE timestamp LIKE ?
               ORDER BY timestamp""",
            (f"{yesterday}%",),
        )
        convs = [dict(row) for row in cur.fetchall()]

    if not convs:
        return {"status": "no_data", "date": yesterday}

    # Build summary prompt
    conv_text = "\n".join([
        f"User: {c['user_message']}\nJarvis: {c['assistant_message']}"
        for c in convs[:30]  # cap at 30 exchanges
    ])

    system_prompt = """You are summarizing a day's worth of conversations between a user and Jarvis (AI assistant).
Extract:
1. A brief summary of the day (2-3 sentences)
2. Key insights or patterns (bullet points)
3. Any new facts learned about the user

Respond in JSON format:
{
  "summary": "...",
  "key_insights": "...",
  "new_facts": [{"key": "...", "value": "..."}]
}"""

    response = await call_ai_chat(conv_text, system_prompt=system_prompt)

    summary_text = ""
    key_insights = ""
    if response:
        try:
            text = response.strip()
            if text.startswith("```"):
                lines = text.split("\n")
                text = "\n".join(lines[1:-1]) if lines[-1].strip() == "```" else "\n".join(lines[1:])
            parsed = json.loads(text)
            summary_text = parsed.get("summary", response)
            key_insights = parsed.get("key_insights", "")

            # Store any new facts discovered
            for fact in parsed.get("new_facts", []):
                if fact.get("key") and fact.get("value"):
                    with db_cursor() as cur:
                        cur.execute(
                            """INSERT INTO facts (key, value, timestamp, confidence)
                               VALUES (?, ?, ?, 0.7)
                               ON CONFLICT(key) DO NOTHING""",
                            (fact["key"].lower(), fact["value"], datetime.utcnow().isoformat()),
                        )
        except Exception:
            summary_text = response

    if not summary_text:
        summary_text = f"Processed {len(convs)} conversations from {yesterday}."

    # Store summary
    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO daily_summaries (date, summary_text, key_insights)
               VALUES (?, ?, ?)
               ON CONFLICT(date) DO UPDATE SET
                   summary_text=excluded.summary_text,
                   key_insights=excluded.key_insights""",
            (yesterday, summary_text, key_insights),
        )

    return {
        "status": "ok",
        "date": yesterday,
        "conversations_processed": len(convs),
        "summary": summary_text,
    }


async def nightly_summarize():
    """Scheduled nightly summarization job."""
    logger.info("Running nightly summarization...")
    try:
        await summarize()
        logger.info("Nightly summarization complete")
    except Exception as e:
        logger.error(f"Nightly summarization failed: {e}")


@app.get("/health")
async def health():
    """Health check with counts."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM facts")
        facts_count = cur.fetchone()["c"]

        cur.execute("SELECT COUNT(*) as c FROM behavior_rules WHERE active=1")
        rules_count = cur.fetchone()["c"]

    # ChromaDB count
    memories_count = 0
    collection = get_chroma()
    if collection:
        try:
            memories_count = collection.count()
        except Exception:
            pass

    return {
        "status": "ok",
        "facts_count": facts_count,
        "rules_count": rules_count,
        "memories_count": memories_count,
    }


@app.get("/")
async def root():
    return {"service": "Jarvis Memory Engine", "version": "1.0.0", "status": "running"}
