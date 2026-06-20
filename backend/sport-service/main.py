"""
Jarvis Sport Service - Port 8006
Simple, solid CRUD service for workouts with SQLite.
"""

import os
import uuid
import sqlite3
import threading
import logging
from datetime import datetime, date, timedelta
from typing import Optional
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Query
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_PATH = os.getenv("DB_PATH", "/app/data/sport.db")
WEEKLY_GOAL = int(os.getenv("WEEKLY_GOAL", "6"))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sport-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Sport Service", version="1.0.0")

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
            CREATE TABLE IF NOT EXISTS workouts (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL DEFAULT '',
                duration_min INTEGER NOT NULL DEFAULT 0,
                calories INTEGER NOT NULL DEFAULT 0,
                date TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts(date DESC);
        """)
    logger.info("Sport database initialized")


def row_to_workout(row: sqlite3.Row) -> dict:
    """Convert a DB row to a workout dict."""
    return dict(row)


def _week_bounds(today: date):
    """Return (monday, sunday) of the week containing today."""
    monday = today - timedelta(days=today.weekday())
    sunday = monday + timedelta(days=6)
    return monday, sunday


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Sport service started")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/workouts")
async def list_workouts(
    week: Optional[str] = Query(None, description="Filter by ISO week YYYY-WW"),
    limit: Optional[int] = Query(None, description="Limit number of results"),
):
    """List workouts, newest first. Optional week filter or limit."""
    with db_cursor() as cur:
        if week:
            cur.execute("SELECT * FROM workouts ORDER BY date DESC, created_at DESC")
            rows = cur.fetchall()
            filtered = []
            for r in rows:
                try:
                    d = date.fromisoformat(r["date"][:10])
                    iso_year, iso_week, _ = d.isocalendar()
                    if f"{iso_year:04d}-{iso_week:02d}" == week:
                        filtered.append(r)
                except (ValueError, TypeError):
                    continue
            rows = filtered
        elif limit is not None and limit > 0:
            cur.execute(
                "SELECT * FROM workouts ORDER BY date DESC, created_at DESC LIMIT ?",
                (limit,),
            )
            rows = cur.fetchall()
        else:
            cur.execute("SELECT * FROM workouts ORDER BY date DESC, created_at DESC")
            rows = cur.fetchall()

    workouts = [row_to_workout(r) for r in rows]
    return {"workouts": workouts, "count": len(workouts)}


@app.post("/workouts", status_code=201)
async def create_workout(request: dict):
    """
    Create a new workout.
    Input: {type, duration_min, calories, date}
    """
    w_type = str(request.get("type", "")).strip()
    duration_min = int(request.get("duration_min", 0) or 0)
    calories = int(request.get("calories", 0) or 0)
    w_date = str(request.get("date", "")).strip() or date.today().isoformat()

    now = datetime.utcnow().isoformat()
    workout_id = str(uuid.uuid4())

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO workouts
               (id, type, duration_min, calories, date, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (workout_id, w_type, duration_min, calories, w_date, now),
        )

    return {
        "id": workout_id,
        "type": w_type,
        "duration_min": duration_min,
        "calories": calories,
        "date": w_date,
        "created_at": now,
    }


@app.delete("/workouts/{workout_id}")
async def delete_workout(workout_id: str):
    """Delete a workout by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT id FROM workouts WHERE id=?", (workout_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Workout not found")

    with db_cursor() as cur:
        cur.execute("DELETE FROM workouts WHERE id=?", (workout_id,))

    return {"status": "deleted", "id": workout_id}


@app.get("/sport/stats")
async def sport_stats():
    """Weekly and monthly workout stats with streak and week-day breakdown."""
    today = date.today()
    monday, sunday = _week_bounds(today)
    month_prefix = today.strftime("%Y-%m")

    with db_cursor() as cur:
        # This week count
        cur.execute(
            "SELECT * FROM workouts WHERE substr(date, 1, 10) BETWEEN ? AND ?",
            (monday.isoformat(), sunday.isoformat()),
        )
        week_rows = cur.fetchall()

        # Month totals
        cur.execute(
            "SELECT COALESCE(SUM(duration_min), 0) AS m, COUNT(*) AS c "
            "FROM workouts WHERE substr(date, 1, 7)=?",
            (month_prefix,),
        )
        month_row = cur.fetchone()
        total_minutes_month = month_row["m"] or 0
        total_workouts_month = month_row["c"] or 0

        # All workout dates for streak computation
        cur.execute("SELECT DISTINCT substr(date, 1, 10) AS d FROM workouts")
        workout_days = set()
        for r in cur.fetchall():
            if r["d"]:
                workout_days.add(r["d"])

    # Days in this week that have a workout
    week_day_dates = {}
    for r in week_rows:
        try:
            d = date.fromisoformat(r["date"][:10])
            week_day_dates[d] = True
        except (ValueError, TypeError):
            continue

    day_labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    week_days = []
    for i in range(7):
        d = monday + timedelta(days=i)
        week_days.append({"day": day_labels[i], "done": d in week_day_dates})

    this_week_count = len(week_day_dates)

    # Current streak: consecutive days with a workout ending today (or yesterday).
    current_streak = 0
    cursor_day = today
    if today.isoformat() not in workout_days:
        # Allow streak to count if yesterday had a workout but today not yet.
        cursor_day = today - timedelta(days=1)
    while cursor_day.isoformat() in workout_days:
        current_streak += 1
        cursor_day -= timedelta(days=1)

    return {
        "this_week_count": this_week_count,
        "weekly_goal": WEEKLY_GOAL,
        "total_minutes_month": total_minutes_month,
        "total_workouts_month": total_workouts_month,
        "current_streak": current_streak,
        "week_days": week_days,
    }


@app.get("/health")
async def health():
    """Health check with workout count."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM workouts")
        workout_count = cur.fetchone()["c"]

    return {"status": "ok", "workout_count": workout_count}


@app.get("/")
async def root():
    return {"service": "Jarvis Sport Service", "version": "1.0.0", "status": "running"}
