"""
Jarvis Finance Service - Port 8005
Simple, solid CRUD service for financial transactions with SQLite.
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
DB_PATH = os.getenv("DB_PATH", "/app/data/finance.db")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("finance-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Jarvis Finance Service", version="1.0.0")

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
            CREATE TABLE IF NOT EXISTS transactions (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL DEFAULT 0,
                type TEXT NOT NULL DEFAULT 'expense',
                category TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                date TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date DESC);
            CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type);
        """)
    logger.info("Finance database initialized")


def row_to_tx(row: sqlite3.Row) -> dict:
    """Convert a DB row to a transaction dict."""
    return dict(row)


def _current_month() -> str:
    return date.today().strftime("%Y-%m")


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Finance service started")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/transactions")
async def list_transactions(
    type: Optional[str] = Query(None, description="Filter by 'income' or 'expense'"),
    month: Optional[str] = Query(None, description="Filter by month YYYY-MM"),
):
    """List transactions, newest first. Optional type and month filters."""
    clauses = []
    params = []
    if type:
        clauses.append("type=?")
        params.append(type)
    if month:
        clauses.append("substr(date, 1, 7)=?")
        params.append(month)

    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    with db_cursor() as cur:
        cur.execute(
            f"SELECT * FROM transactions {where} ORDER BY date DESC, created_at DESC",
            tuple(params),
        )
        rows = cur.fetchall()

    txs = [row_to_tx(r) for r in rows]
    return {"transactions": txs, "count": len(txs)}


@app.post("/transactions", status_code=201)
async def create_transaction(request: dict):
    """
    Create a new transaction.
    Input: {amount, type, category, description, date}
    """
    amount = abs(float(request.get("amount", 0) or 0))
    tx_type = str(request.get("type", "expense")).strip().lower()
    if tx_type not in ("income", "expense"):
        tx_type = "expense"
    category = str(request.get("category", "")).strip()
    description = str(request.get("description", "")).strip()
    tx_date = str(request.get("date", "")).strip() or date.today().isoformat()

    now = datetime.utcnow().isoformat()
    tx_id = str(uuid.uuid4())

    with db_cursor() as cur:
        cur.execute(
            """INSERT INTO transactions
               (id, amount, type, category, description, date, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (tx_id, amount, tx_type, category, description, tx_date, now),
        )

    return {
        "id": tx_id,
        "amount": amount,
        "type": tx_type,
        "category": category,
        "description": description,
        "date": tx_date,
        "created_at": now,
    }


@app.delete("/transactions/{tx_id}")
async def delete_transaction(tx_id: str):
    """Delete a transaction by ID."""
    with db_cursor() as cur:
        cur.execute("SELECT id FROM transactions WHERE id=?", (tx_id,))
        row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Transaction not found")

    with db_cursor() as cur:
        cur.execute("DELETE FROM transactions WHERE id=?", (tx_id,))

    return {"status": "deleted", "id": tx_id}


@app.get("/finance/stats")
async def finance_stats(
    month: Optional[str] = Query(None, description="Month YYYY-MM, defaults to current"),
):
    """Monthly stats: balance, income, expenses, by-category breakdown."""
    target_month = month or _current_month()

    with db_cursor() as cur:
        cur.execute(
            "SELECT COALESCE(SUM(amount), 0) AS t FROM transactions "
            "WHERE type='income' AND substr(date, 1, 7)=?",
            (target_month,),
        )
        total_income = cur.fetchone()["t"] or 0

        cur.execute(
            "SELECT COALESCE(SUM(amount), 0) AS t FROM transactions "
            "WHERE type='expense' AND substr(date, 1, 7)=?",
            (target_month,),
        )
        total_expenses = cur.fetchone()["t"] or 0

        cur.execute(
            "SELECT category, COALESCE(SUM(amount), 0) AS total FROM transactions "
            "WHERE type='expense' AND substr(date, 1, 7)=? "
            "GROUP BY category ORDER BY total DESC",
            (target_month,),
        )
        by_category = [
            {"category": r["category"], "total": r["total"]} for r in cur.fetchall()
        ]

        cur.execute(
            "SELECT COUNT(*) AS c FROM transactions WHERE substr(date, 1, 7)=?",
            (target_month,),
        )
        transaction_count = cur.fetchone()["c"]

    biggest_category = by_category[0]["category"] if by_category else None

    return {
        "month": target_month,
        "balance": total_income - total_expenses,
        "total_income": total_income,
        "total_expenses": total_expenses,
        "by_category": by_category,
        "biggest_category": biggest_category,
        "transaction_count": transaction_count,
    }


@app.get("/finance/summary")
async def finance_summary():
    """Last 7 days income vs expense totals per day (for a bar chart)."""
    today = date.today()
    days = [(today - timedelta(days=i)) for i in range(6, -1, -1)]

    summary = []
    with db_cursor() as cur:
        for d in days:
            iso = d.isoformat()
            cur.execute(
                "SELECT COALESCE(SUM(amount), 0) AS t FROM transactions "
                "WHERE type='income' AND substr(date, 1, 10)=?",
                (iso,),
            )
            income = cur.fetchone()["t"] or 0
            cur.execute(
                "SELECT COALESCE(SUM(amount), 0) AS t FROM transactions "
                "WHERE type='expense' AND substr(date, 1, 10)=?",
                (iso,),
            )
            expense = cur.fetchone()["t"] or 0
            summary.append({"date": iso, "income": income, "expense": expense})

    return {"summary": summary}


@app.get("/health")
async def health():
    """Health check with transaction count."""
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) as c FROM transactions")
        transaction_count = cur.fetchone()["c"]

    return {"status": "ok", "transaction_count": transaction_count}


@app.get("/")
async def root():
    return {"service": "Jarvis Finance Service", "version": "1.0.0", "status": "running"}
