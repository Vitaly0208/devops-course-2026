import os

import psycopg2
from flask import Flask

app = Flask(__name__)


def connect_db():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        dbname=os.getenv("POSTGRES_DB", "app"),
        user=os.getenv("POSTGRES_USER", "app"),
        password=os.getenv("POSTGRES_PASSWORD", ""),
    )


@app.get("/health")
def health():
    return "ok\n", 200


@app.get("/")
def index():
    with connect_db() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                "id BIGSERIAL PRIMARY KEY)"
            )
            cursor.execute("INSERT INTO visits DEFAULT VALUES")
            cursor.execute("SELECT COUNT(*) FROM visits")
            visits = cursor.fetchone()[0]

    return f"Hello from Docker, Vitaly! Visits: {visits}\n", 200
