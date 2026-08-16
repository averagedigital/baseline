#!/usr/bin/env python3
"""Build nutrition.sqlite from local JSON or CSV datasets; never downloads data."""
from __future__ import annotations

import csv
import json
import sqlite3
import sys
from pathlib import Path


def rows(path: Path):
    if path.suffix.lower() == ".json":
        yield from json.loads(path.read_text(encoding="utf-8"))
        return
    with path.open(newline="", encoding="utf-8") as handle:
        yield from csv.DictReader(handle)


def normalize(value: str) -> str:
    return " ".join("".join(char.lower() if char.isalnum() else " " for char in value).split())


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_nutrition_database.py INPUT.json|INPUT.csv OUTPUT.sqlite")
    input_path, output_path = map(Path, sys.argv[1:])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    if temporary_path.exists():
        temporary_path.unlink()
    connection = sqlite3.connect(temporary_path)
    connection.executescript("""
    CREATE TABLE foods (id INTEGER PRIMARY KEY, canonical_name TEXT NOT NULL, normalized_name TEXT NOT NULL, kcal_per_100g REAL, protein_per_100g REAL, fat_per_100g REAL, carbs_per_100g REAL, source TEXT NOT NULL);
    CREATE TABLE food_aliases (food_id INTEGER NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL);
    CREATE INDEX idx_foods_normalized_name ON foods(normalized_name);
    CREATE INDEX idx_aliases_normalized_alias ON food_aliases(normalized_alias);
    CREATE INDEX idx_aliases_food_id ON food_aliases(food_id);
    """)
    try:
        with connection:
            for line, item in enumerate(rows(input_path), 1):
                if not item.get("canonical_name") or item.get("kcal_per_100g") in (None, ""):
                    raise ValueError(f"malformed row {line}: canonical_name and kcal_per_100g are required")
                name = str(item["canonical_name"])
                cursor = connection.execute("INSERT INTO foods(canonical_name, normalized_name, kcal_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g, source) VALUES (?, ?, ?, ?, ?, ?, ?)", (name, normalize(name), item.get("kcal_per_100g"), item.get("protein_per_100g"), item.get("fat_per_100g"), item.get("carbs_per_100g"), item.get("source", input_path.name)))
                aliases = item.get("aliases", [])
                if isinstance(aliases, str): aliases = [value.strip() for value in aliases.split("|") if value.strip()]
                connection.executemany("INSERT INTO food_aliases(food_id, alias, normalized_alias) VALUES (?, ?, ?)", [(cursor.lastrowid, alias, normalize(alias)) for alias in aliases])
    finally:
        connection.close()
    temporary_path.replace(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
