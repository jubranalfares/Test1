"""
Jarvis Goals Service - Port 8004
Simple, solid CRUD service for goals/habits with SQLite.
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
DB_PATH = os.getenv("DB_PATH", "/app/data/goals.db")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("goals-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Goals Service", version="1.0.0")

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
            CREATE TABLE IF NOT EXISTS goals (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL DEFAULT '',
                target_value REAL NOT NULL DEFAULT 0,
                current_value REAL NOT NULL DEFAULT 0,
                unit TEXT NOT NULL DEFAULT '',
                deadline TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                completed INTEGER NOT NULL DEFAULT 0,
                streak INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_goals_created_at ON goals(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_goals_completed ON goals(completed);
        """)
    logger.info("Goals database initialized")


def _parse_date(value: str) -> Optional[date]:
    """Parse an ISO date or datetime string into a date object."""
    if not value:
        return None
    try:
        return date.fromisoformat(value[:10])
    except (ValueError, TypeError):
        try:
            return datetime.fromisoformat(value).date()
        except (ValueError, TypeError):
            return None


def row_to_goal(row: sqlite3.Row) -> dict:
    """Convert a DB row to a goal dict with computed status and progress."""
    goal = dict(row)
    goal["completed"] = bool(goal.get("completed", 0))

    target = goal.get("target_value") or 0
    current = goal.get("current_value") or 0

    if target > 0:
        progress = current / target
    else:
        progress = 1.0 if goal["completed"] else 0.0
    progress = max(0.0, min(progress, 1.0)) if not goal["completed"] else (progress if target > 0 else 1.0)
    goal["progress_percent"] = round(min(progress, 1.0) * 100, 1)

    today = date.today()
    created = _parse_date(goal.get("created_at"))
    deadline = _parse_date(goal.get("deadline"))

    if goal["completed"] or (target > 0 and current >= target):
        status = "done"
    elif deadline is not None and today > deadline:
        status = "behind"
    else:
        # Expected progress by now, linear from created_at to deadline.
        if created is not None and deadline is not None and deadline > created:
            total_days = (deadline - created).days
            elapsed_days = (today - created).days
            elapsed_days = max(0, min(elapsed_days, total_days))
            expected = elapsed_days / total_days if total_days > 0 else 1.0
        else:
            expected = 0.0
        if progress >= expected:
            status = "on_track"
        else:
            status = "at_risk"

    goal["status"] = status
    return goal


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Goals service started")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/goals")
async def list_goals():
    """List all goals, newest first, with computed status and progress."""
    with db_cursor() as cur:
        cur.execute("SELECT * FROM goals ORDER BY created_at DESC")
        rows = cur.fetchall()

    goals = [row_to_goal(r) for r in rows]
    return {"goals": goals, "count": len(goals)}


@app.post("/goals", status_code=201)
async def create_goal(request: dict):
    """
    Create a new goal.
    Input: {title, target_value, unit, deadline, current_value=0}
    """
    title = str(request.get("title", "")).strip()
    target_value = float(request.get("target_value", 0) or 0)
    current_value = float(request.get("current_value", 0) or 0)
    unit = str(request.get("unit", "")).strip()
    deadline = str(request.get("deadline", "")).strip()

    now = datetime.utcnow().isoformat()
    goal_id = str(uuid.uuid4())
    completed = 1 if (target_value > 0 and current_value >= target_value) else 0

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO goals
               (id, title, target_value, current_value, unit, deadline,
                created_at, updated_at, completed, streak)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (goal_id, title, target_value, current_value, unit, deadline,
             now, now, completed, 0),
        )
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        row = cur.fetchone()

    return row_to_goal(row)


@app.get("/goals/stats")
async def goals_stats():
    """Aggregate stats: active, completed, completed this month, best streak."""
    month_prefix = date.today().strftime("%Y-%m")
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) AS c FROM goals WHERE completed=0")
        active_count = cur.fetchone()["c"]

        cur.execute("SELECT COUNT(*) AS c FROM goals WHERE completed=1")
        completed_count = cur.fetchone()["c"]

        cur.execute(
            "SELECT COUNT(*) AS c FROM goals WHERE completed=1 AND substr(updated_at, 1, 7)=?",
            (month_prefix,),
        )
        completed_this_month = cur.fetchone()["c"]

        cur.execute("SELECT MAX(streak) AS s FROM goals")
        best_streak = cur.fetchone()["s"] or 0

    return {
        "active_count": active_count,
        "completed_count": completed_count,
        "completed_this_month": completed_this_month,
        "best_streak": best_streak,
    }


@app.get("/goals/{goal_id}")
async def get_goal(goal_id: str):
    """Get a single goal by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Goal not found")

    return row_to_goal(row)


@app.put("/goals/{goal_id}")
async def update_goal(goal_id: str, request: dict):
    """Update a goal (partial update — only provided fields are changed)."""
    with db_cursor() as cur:
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Goal not found")

    current = dict(row)
    now = datetime.utcnow().isoformat()

    title = str(request.get("title", current["title"]))
    target_value = float(request.get("target_value", current["target_value"]) or 0)
    current_value = float(request.get("current_value", current["current_value"]) or 0)
    unit = str(request.get("unit", current["unit"]))
    deadline = str(request.get("deadline", current["deadline"]))
    streak = int(request.get("streak", current["streak"]) or 0)

    if "completed" in request:
        completed = int(bool(request.get("completed")))
    else:
        completed = current["completed"]
    if target_value > 0 and current_value >= target_value:
        completed = 1

    with db_cursor() as cur:
        cur.execute(
            """UPDATE goals
               SET title=?, target_value=?, current_value=?, unit=?, deadline=?,
                   completed=?, streak=?, updated_at=?
               WHERE id=?""",
            (title, target_value, current_value, unit, deadline,
             completed, streak, now, goal_id),
        )
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        updated = cur.fetchone()

    return row_to_goal(updated)


@app.delete("/goals/{goal_id}")
async def delete_goal(goal_id: str):
    """Delete a goal by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT id FROM goals WHERE id=?", (goal_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Goal not found")

    with db_cursor() as cur:
        cur.execute("DELETE FROM goals WHERE id=?", (goal_id,))

    return {"status": "deleted", "id": goal_id}


@app.post("/goals/{goal_id}/progress")
async def update_progress(goal_id: str, request: dict):
    """
    Set or increment a goal's current_value.
    Input: {value: float} sets current_value, or {value: float, increment: true}
    to add to the existing value. Marks completed if current >= target.
    """
    with db_cursor() as cur:
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Goal not found")

    current = dict(row)
    value = float(request.get("value", 0) or 0)
    increment = bool(request.get("increment", False))

    if increment:
        new_value = (current["current_value"] or 0) + value
    else:
        new_value = value

    target = current["target_value"] or 0
    completed = 1 if (target > 0 and new_value >= target) else current["completed"]
    now = datetime.utcnow().isoformat()

    with db_cursor() as cur:
        cur.execute(
            "UPDATE goals SET current_value=?, completed=?, updated_at=? WHERE id=?",
            (new_value, completed, now, goal_id),
        )
        cur.execute("SELECT * FROM goals WHERE id=?", (goal_id,))
        updated = cur.fetchone()

    return row_to_goal(updated)


@app.get("/health")
async def health():
    """Health check with goals count."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM goals")
        goals_count = cur.fetchone()["c"]

    return {"status": "ok", "goals_count": goals_count}


@app.get("/")
async def root():
    return {"service": "Jarvis Goals Service", "version": "1.0.0", "status": "running"}
