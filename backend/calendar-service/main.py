"""
Jarvis Calendar Service - Port 8007
Simple, solid CRUD service for calendar events with SQLite.
"""

import os
import uuid
import sqlite3
import threading
import logging
from datetime import datetime, date
from typing import Optional
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Query
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_PATH = os.getenv("DB_PATH", "/app/data/calendar.db")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("calendar-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Calendar Service", version="1.0.0")

# ---------------------------------------------------------------------------
# SQLite with thread lock
# ---------------------------------------------------------------------------
_db_lock = threading.Lock()


def get_db_connection() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


@contextmanager
def db_cursor():
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
    with db_cursor() as cur:
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                start TEXT NOT NULL DEFAULT '',
                end TEXT NOT NULL DEFAULT '',
                reminder_minutes INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_events_start ON events(start);
        """)
    logger.info("Calendar database initialized")


def row_to_event(row: sqlite3.Row) -> dict:
    """Convert a DB row to an event dict."""
    return dict(row)


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Calendar service started")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/events")
async def list_events(
    date: Optional[str] = Query(None, description="Filter by date YYYY-MM-DD"),
):
    """List events, sorted by start. Optional date filter (events on that date)."""
    with db_cursor() as cur:
        if date:
            cur.execute(
                "SELECT * FROM events WHERE substr(start, 1, 10)=? ORDER BY start ASC",
                (date,),
            )
        else:
            cur.execute("SELECT * FROM events ORDER BY start ASC")
        rows = cur.fetchall()

    events = [row_to_event(r) for r in rows]
    return {"events": events, "count": len(events)}


@app.get("/events/today")
async def events_today():
    """Today's events sorted by start."""
    today = date.today().isoformat()
    with db_cursor() as cur:
        cur.execute(
            "SELECT * FROM events WHERE substr(start, 1, 10)=? ORDER BY start ASC",
            (today,),
        )
        rows = cur.fetchall()

    events = [row_to_event(r) for r in rows]
    return {"events": events, "count": len(events)}


@app.post("/events", status_code=201)
async def create_event(request: dict):
    """
    Create a new event.
    Input: {title, description, start, end, reminder_minutes}
    """
    title = str(request.get("title", "")).strip()
    description = str(request.get("description", "")).strip()
    start = str(request.get("start", "")).strip()
    end = str(request.get("end", "")).strip()
    reminder_minutes = int(request.get("reminder_minutes", 0) or 0)

    now = datetime.utcnow().isoformat()
    event_id = str(uuid.uuid4())

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO events
               (id, title, description, start, end, reminder_minutes, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (event_id, title, description, start, end, reminder_minutes, now),
        )

    return {
        "id": event_id,
        "title": title,
        "description": description,
        "start": start,
        "end": end,
        "reminder_minutes": reminder_minutes,
        "created_at": now,
    }


@app.put("/events/{event_id}")
async def update_event(event_id: str, request: dict):
    """Update an event (partial update — only provided fields are changed)."""
    with db_cursor() as cur:
        cur.execute("SELECT * FROM events WHERE id=?", (event_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Event not found")

    current = dict(row)

    title = str(request.get("title", current["title"]))
    description = str(request.get("description", current["description"]))
    start = str(request.get("start", current["start"]))
    end = str(request.get("end", current["end"]))
    reminder_minutes = int(
        request.get("reminder_minutes", current["reminder_minutes"]) or 0
    )

    with db_cursor() as cur:
        cur.execute(
            """UPDATE events
               SET title=?, description=?, start=?, end=?, reminder_minutes=?
               WHERE id=?""",
            (title, description, start, end, reminder_minutes, event_id),
        )
        cur.execute("SELECT * FROM events WHERE id=?", (event_id,))
        updated = cur.fetchone()

    return row_to_event(updated)


@app.delete("/events/{event_id}")
async def delete_event(event_id: str):
    """Delete an event by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT id FROM events WHERE id=?", (event_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Event not found")

    with db_cursor() as cur:
        cur.execute("DELETE FROM events WHERE id=?", (event_id,))

    return {"status": "deleted", "id": event_id}


@app.get("/health")
async def health():
    """Health check with event count."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM events")
        event_count = cur.fetchone()["c"]

    return {"status": "ok", "event_count": event_count}


@app.get("/")
async def root():
    return {"service": "Jarvis Calendar Service", "version": "1.0.0", "status": "running"}
