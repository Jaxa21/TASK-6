from pathlib import Path

import psycopg
from psycopg.rows import dict_row

SQL_DIR = Path(__file__).resolve().parent / "sql"
USERS_SQL = """
SELECT pos + 1 AS "No.", full_name AS "Name", gender AS "Sex", address AS "Address",
       latitude || ', ' || longitude AS "Coordinates", height_cm || ' cm, ' || weight_kg || ' kg' AS "Body",
       eye_color AS "Eyes", hair_color AS "Hair", phone AS "Phone", email AS "E-mail"
  FROM faker.fake_users(%s, %s, %s, %s)"""


class FakerDb:
    def __init__(self, dsn: str):
        self.dsn = dsn

    def _query(self, sql: str, *params) -> list[dict]:
        with psycopg.connect(self.dsn, row_factory=dict_row) as conn:
            return conn.execute(sql, params).fetchall()

    def locales(self) -> dict[str, str]:
        return {r["code"]: r["name"] for r in self._query("SELECT code, name FROM faker.locales ORDER BY code DESC")}

    def users(self, locale: str, seed: int, batch: int, size: int) -> list[dict]:
        return self._query(USERS_SQL, locale, seed, batch, size)

    def install(self) -> None:
        with psycopg.connect(self.dsn, autocommit=True) as conn:
            for name in ("schema.sql", "functions.sql", "data.sql"):
                conn.execute((SQL_DIR / name).read_text(encoding="utf-8"))
