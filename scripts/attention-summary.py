#!/usr/bin/env python3
"""One-shot calendar snapshot for the shared bar indicators."""

import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from attention import backend


def main():
    today = date.today()
    start = today.replace(day=1)
    end = date(start.year + (start.month == 12), start.month % 12 + 1, 1)
    try:
        result = backend.handle(
            {"op": "nextcloud", "start": start.isoformat(), "end": end.isoformat()}
        )
        if result.get("refresh_due"):
            result = backend.handle(
                {
                    "op": "nextcloud",
                    "start": start.isoformat(),
                    "end": end.isoformat(),
                    "refresh": True,
                }
            )
        print(json.dumps({"cloud": result, "month": start.strftime("%Y-%m")}))
    except (ValueError, OSError) as error:
        print(json.dumps({"error": str(error)}))


if __name__ == "__main__":
    main()
