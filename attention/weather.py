"""Open-Meteo forecast for the location configured in attention.json."""

import json
import os
from pathlib import Path
import time
from datetime import datetime
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


API = "https://api.open-meteo.com/v1/forecast"
CACHE_AGE = 15 * 60


class WeatherError(ValueError):
    pass


def condition(code, is_day=True):
    code = int(code)
    if code == 0:
        return ("Clear sky", "sun" if is_day else "moon")
    if code == 1:
        return ("Mainly clear", "sun" if is_day else "moon")
    if code == 2:
        return ("Partly cloudy", "cloud-sun" if is_day else "cloud-moon")
    if code == 3:
        return ("Cloudy", "cloud")
    if code in (45, 48):
        return ("Fog", "cloud-fog")
    if code in (51, 53, 55, 56, 57):
        return ("Drizzle", "cloud-drizzle")
    if code in (61, 63, 65, 66, 67, 80, 81, 82):
        return ("Rain", "cloud-rain")
    if code in (71, 73, 75, 77, 85, 86):
        return ("Snow", "cloud-snow")
    if code in (95, 96, 99):
        return ("Thunderstorm", "cloud-lightning")
    return ("Weather", "cloud")


def normalize(payload, location):
    current = payload["current"]
    daily = payload["daily"]
    keys = ("time", "weather_code", "temperature_2m_max", "temperature_2m_min")
    if any(len(daily[key]) < 7 for key in keys):
        raise WeatherError("The weather service returned an incomplete forecast.")
    description, icon = condition(current["weather_code"], bool(current["is_day"]))
    return {
        "location": location["name"],
        "observed_at": current["time"],
        "stale": False,
        "current": {
            "temperature": current["temperature_2m"],
            "feels_like": current["apparent_temperature"],
            "humidity": current["relative_humidity_2m"],
            "wind": current["wind_speed_10m"],
            "description": description,
            "icon": icon,
        },
        "days": [
            {
                "date": daily["time"][i],
                "high": daily["temperature_2m_max"][i],
                "low": daily["temperature_2m_min"][i],
                "icon": condition(daily["weather_code"][i])[1],
                "description": condition(daily["weather_code"][i])[0],
            }
            for i in range(7)
        ],
    }


def fetch(location, cache_path, *, opener=urlopen, now=time.time):
    try:
        latitude = float(location["latitude"])
        longitude = float(location["longitude"])
        name = str(location["name"]).strip()
        timezone = str(location["timezone"]).strip()
    except (KeyError, TypeError, ValueError) as error:
        raise WeatherError("Set a name, coordinates, and timezone in attention.json.") from error
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180 and name and timezone):
        raise WeatherError("The weather location in attention.json is invalid.")

    key = [latitude, longitude, timezone]
    cache_path = Path(cache_path)
    cached = None
    try:
        cached = json.loads(cache_path.read_text())
        if cached.get("key") != key:
            cached = None
    except (OSError, ValueError, AttributeError):
        pass
    local_today = datetime.fromtimestamp(now(), ZoneInfo(timezone)).date().isoformat()
    if (cached and now() - cached.get("fetched_at", 0) < CACHE_AGE
            and cached["forecast"]["days"][0]["date"] == local_today):
        return cached["forecast"]

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "timezone": timezone,
        "forecast_days": 7,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
    }
    request = Request(API + "?" + urlencode(params), headers={"User-Agent": "ZephyrusShell/1.0", "Accept": "application/json"})
    try:
        with opener(request, timeout=15) as response:
            forecast = normalize(json.load(response), location)
    except (HTTPError, URLError, OSError, ValueError, KeyError, TypeError) as error:
        if cached:
            return dict(cached["forecast"], stale=True)
        raise WeatherError("Weather is unavailable. Check your connection and try again.") from error

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = cache_path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"key": key, "fetched_at": now(), "forecast": forecast}))
    os.chmod(temporary, 0o600)
    temporary.replace(cache_path)
    return forecast
