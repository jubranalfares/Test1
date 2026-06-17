"""
Jarvis Notes Service - Port 8003
Simple, solid CRUD service for notes with SQLite.
"""

import os
import json
import uuid
import sqlite3
import threading
import logging
from datetime import datetime
from typing import Optional, List
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_PATH = os.getenv("DB_PATH", "/app/data/notes.db")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("notes-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Notes Service", version="1.0.0")

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
            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL DEFAULT '',
                content TEXT NOT NULL DEFAULT '',
                tags TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                color TEXT NOT NULL DEFAULT '#1A1A28'
            );

            CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(pinned DESC);
        """)
    logger.info("Notes database initialized")


def row_to_note(row: sqlite3.Row) -> dict:
    """Convert a DB row to a note dict, parsing JSON tags."""
    note = dict(row)
    try:
        note["tags"] = json.loads(note.get("tags", "[]"))
    except (json.JSONDecodeError, TypeError):
        note["tags"] = []
    note["pinned"] = bool(note.get("pinned", 0))
    return note


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Notes service started")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/notes")
async def list_notes(
    q: Optional[str] = Query(None, description="Search in title and content"),
    tag: Optional[str] = Query(None, description="Filter by tag"),
):
    """List all notes, newest first. Optional text search and tag filter."""
    with db_cursor() as cur:
        if q and tag:
            search = f"%{q}%"
            cur.execute(
                """SELECT * FROM notes
                   WHERE (title LIKE ? OR content LIKE ?)
                     AND tags LIKE ?
                   ORDER BY pinned DESC, created_at DESC""",
                (search, search, f"%{tag}%"),
            )
        elif q:
            search = f"%{q}%"
            cur.execute(
                """SELECT * FROM notes
                   WHERE title LIKE ? OR content LIKE ?
                   ORDER BY pinned DESC, created_at DESC""",
                (search, search),
            )
        elif tag:
            cur.execute(
                """SELECT * FROM notes
                   WHERE tags LIKE ?
                   ORDER BY pinned DESC, created_at DESC""",
                (f"%{tag}%",),
            )
        else:
            cur.execute("SELECT * FROM notes ORDER BY pinned DESC, created_at DESC")

        rows = cur.fetchall()

    notes = [row_to_note(r) for r in rows]
    return {"notes": notes, "count": len(notes)}


@app.post("/notes", status_code=201)
async def create_note(request: dict):
    """
    Create a new note.
    Input: {title, content, tags=[], color="#1A1A28", pinned=false}
    """
    title = request.get("title", "").strip()
    content = request.get("content", "").strip()
    tags = request.get("tags", [])
    color = request.get("color", "#1A1A28")
    pinned = bool(request.get("pinned", False))

    if not isinstance(tags, list):
        tags = []

    now = datetime.utcnow().isoformat()
    note_id = str(uuid.uuid4())

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO notes (id, title, content, tags, created_at, updated_at, pinned, color)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (note_id, title, content, json.dumps(tags), now, now, int(pinned), color),
        )

    return {
        "id": note_id,
        "title": title,
        "content": content,
        "tags": tags,
        "created_at": now,
        "updated_at": now,
        "pinned": pinned,
        "color": color,
    }


@app.get("/notes/tags")
async def list_tags():
    """List all unique tags with occurrence counts."""
    with db_cursor() as cur:
        cur.execute("SELECT tags FROM notes WHERE tags != '[]' AND tags != ''")
        rows = cur.fetchall()

    tag_counts: dict = {}
    for row in rows:
        try:
            tags = json.loads(row["tags"])
            for tag in tags:
                if tag:
                    tag_counts[tag] = tag_counts.get(tag, 0) + 1
        except Exception:
            pass

    tags_list = [{"tag": k, "count": v} for k, v in sorted(tag_counts.items(), key=lambda x: -x[1])]
    return {"tags": tags_list, "count": len(tags_list)}


@app.get("/notes/{note_id}")
async def get_note(note_id: str):
    """Get a single note by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT * FROM notes WHERE id=?", (note_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Note not found")

    return row_to_note(row)


@app.put("/notes/{note_id}")
async def update_note(note_id: str, request: dict):
    """
    Update a note (partial update OK — only provided fields are changed).
    """
    with db_cursor() as cur:
        cur.execute("SELECT * FROM notes WHERE id=?", (note_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Note not found")

    current = row_to_note(row)
    now = datetime.utcnow().isoformat()

    # Apply partial updates
    title = request.get("title", current["title"])
    content = request.get("content", current["content"])
    tags = request.get("tags", current["tags"])
    color = request.get("color", current["color"])
    pinned = request.get("pinned", current["pinned"])

    if not isinstance(tags, list):
        tags = current["tags"]

    with db_cursor() as cur:
        cur.execute(
            """UPDATE notes
               SET title=?, content=?, tags=?, color=?, pinned=?, updated_at=?
               WHERE id=?""",
            (title, content, json.dumps(tags), color, int(bool(pinned)), now, note_id),
        )

    return {
        "id": note_id,
        "title": title,
        "content": content,
        "tags": tags,
        "color": color,
        "pinned": bool(pinned),
        "created_at": current["created_at"],
        "updated_at": now,
    }


@app.delete("/notes/{note_id}")
async def delete_note(note_id: str):
    """Delete a note by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT id FROM notes WHERE id=?", (note_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Note not found")

    with db_cursor() as cur:
        cur.execute("DELETE FROM notes WHERE id=?", (note_id,))

    return {"status": "deleted", "id": note_id}


@app.post("/notes/{note_id}/pin")
async def toggle_pin(note_id: str):
    """Toggle pin status of a note."""
    with db_cursor() as cur:
        cur.execute("SELECT id, pinned FROM notes WHERE id=?", (note_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Note not found")

    new_pinned = 0 if row["pinned"] else 1
    now = datetime.utcnow().isoformat()

    with db_cursor() as cur:
        cur.execute(
            "UPDATE notes SET pinned=?, updated_at=? WHERE id=?",
            (new_pinned, now, note_id),
        )

    return {"id": note_id, "pinned": bool(new_pinned)}


@app.get("/health")
async def health():
    """Health check with notes count."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM notes")
        notes_count = cur.fetchone()["c"]

    return {"status": "ok", "notes_count": notes_count}


@app.get("/")
async def root():
    return {"service": "Jarvis Notes Service", "version": "1.0.0", "status": "running"}
