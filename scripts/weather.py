"""One-shot cached weather shared by the bar and Attention panel."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from attention.backend import handle

try:
    print(json.dumps({"forecast": handle({"op": "weather"})}))
except (ValueError, OSError) as error:
    print(json.dumps({"error": str(error)}))
