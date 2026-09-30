"""Open-Meteo forecast for the location configured in attention.json."""

import json
import os
from collections import Counter
from pathlib import Path
import time
from datetime import datetime
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


API = "https://api.open-meteo.com/v1/forecast"
CACHE_AGE = 15 * 60
CACHE_VERSION = 3


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


def condition_group(code):
    if code in (0, 1):
        return "sun"
    if code == 2:
        return "mixed"
    if code == 3:
        return "cloud"
    if code in (56, 57, 66, 67):
        return "freezing"
    return {"cloud-fog": "fog", "cloud-drizzle": "drizzle", "cloud-rain": "rain",
            "cloud-snow": "snow", "cloud-lightning": "storm"}.get(condition(code)[1], "cloud")


def daily_outlook(rows, fallback_code):
    """Summarize a full local day; daylight defines sky, all hours define wet weather."""
    daylight = [row for row in rows if row["is_day"]]
    if len(rows) < 18 or not daylight:
        description, icon = condition(fallback_code)
        return {"description": description, "icon": icon, "summary_source": "daily"}

    wet_groups = ("storm", "freezing", "snow", "rain", "drizzle")
    counts = Counter(row["group"] for row in rows)
    day_counts = Counter(row["group"] for row in daylight)
    wet = sum(counts[group] for group in wet_groups)
    day_wet = sum(day_counts[group] for group in wet_groups)
    if wet >= len(rows) / 2 or day_wet >= len(daylight) / 2:
        primary = max(wet_groups, key=lambda group: (counts[group], -wet_groups.index(group)))
    else:
        primary = day_counts.most_common(1)[0][0]
        if primary in wet_groups or day_counts[primary] < len(daylight) * 0.6:
            primary = "mixed" if day_counts["sun"] + day_counts["mixed"] else "cloud"

    descriptions = {"sun": "Mostly sunny", "mixed": "A mix of sun and cloud", "cloud": "Mostly cloudy",
                    "fog": "Mostly foggy", "drizzle": "Drizzle for much of the day",
                    "rain": "Rain for much of the day", "snow": "Snow for much of the day",
                    "storm": "Thunderstorms for much of the day", "freezing": "Freezing rain for much of the day"}
    icons = {"sun": "sun", "mixed": "cloud-sun", "cloud": "cloud", "fog": "cloud-fog",
             "drizzle": "cloud-drizzle", "rain": "cloud-rain", "snow": "cloud-snow",
             "storm": "cloud-lightning", "freezing": "cloud-rain"}
    description = descriptions[primary]
    # Include short hazardous spells even when they do not determine the day's icon.
    secondary_groups = [group for group in (*wet_groups, "fog") if group != primary and counts[group]]
    details = []
    for secondary in secondary_groups:
        affected = [row for row in rows if row["group"] == secondary]
        periods = {"overnight" if row["hour"] < 6 or row["hour"] >= 22 else
                   "in the morning" if row["hour"] < 12 else
                   "in the afternoon" if row["hour"] < 18 else "in the evening" for row in affected}
        name = {"storm": "thunderstorms", "freezing": "freezing rain", "snow": "snow",
                "rain": "rain", "drizzle": "drizzle", "fog": "fog"}[secondary]
        details.append(name + " " + next(iter(periods)) if len(periods) == 1 else name + " at times")
    if details:
        description += ", with " + (", ".join(details[:-1]) + " and " + details[-1] if len(details) > 1 else details[0])
    if primary in wet_groups:
        if day_counts["sun"]:
            description += " and sunny breaks" if details else ", with sunny breaks"
        elif wet < len(rows):
            description += " and dry breaks" if details else ", with dry breaks"
    elif not details:
        if primary == "sun" and day_counts["cloud"]:
            description += ", with cloudy spells"
        elif primary in ("cloud", "fog") and day_counts["sun"]:
            description += ", with sunny spells"
    return {"description": description, "icon": icons[primary], "summary_source": "hourly"}


def normalize(payload, location):
    current = payload["current"]
    daily = payload["daily"]
    keys = ("time", "weather_code", "temperature_2m_max", "temperature_2m_min")
    if any(len(daily[key]) < 7 for key in keys):
        raise WeatherError("The weather service returned an incomplete forecast.")
    description, icon = condition(current["weather_code"], bool(current["is_day"]))
    hourly = payload.get("hourly", {})
    hours = []
    day_hours = {}
    hourly_keys = ("temperature_2m", "weather_code", "is_day", "precipitation_probability")
    times = hourly.get("time", [])
    if any(len(hourly.get(key, [])) != len(times) for key in hourly_keys):
        raise WeatherError("The weather service returned an incomplete hourly forecast.")
    for i, timestamp in enumerate(times):
        code = hourly["weather_code"][i]
        if code is not None and hourly["is_day"][i] is not None:
            day_hours.setdefault(timestamp[:10], []).append({"group": condition_group(int(code)),
                "hour": int(timestamp[11:13]), "is_day": bool(hourly["is_day"][i])})
        if timestamp <= current["time"]:
            continue
        if len(hours) == 24:
            continue
        if hourly["temperature_2m"][i] is None or hourly["weather_code"][i] is None:
            continue
        hour_description, hour_icon = condition(hourly["weather_code"][i], bool(hourly["is_day"][i]))
        hours.append({"time": timestamp, "temperature": hourly["temperature_2m"][i],
                      "icon": hour_icon, "description": hour_description,
                      "precipitation_probability": hourly["precipitation_probability"][i]})
    return {
        "location": location["name"],
        "observed_at": current["time"],
        "stale": False,
        "hours": hours,
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
                **daily_outlook(day_hours.get(daily["time"][i], []), daily["weather_code"][i]),
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
    if (cached and cached.get("version") == CACHE_VERSION
            and now() - cached.get("fetched_at", 0) < CACHE_AGE
            and cached["forecast"]["days"][0]["date"] == local_today):
        return dict(cached["forecast"], local_date=local_today)

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "timezone": timezone,
        "forecast_days": 7,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "hourly": "temperature_2m,weather_code,is_day,precipitation_probability",
    }
    request = Request(API + "?" + urlencode(params), headers={"User-Agent": "ZephyrusShell/1.0", "Accept": "application/json"})
    try:
        with opener(request, timeout=15) as response:
            forecast = normalize(json.load(response), location)
    except (HTTPError, URLError, OSError, ValueError, KeyError, TypeError) as error:
        if cached:
            return dict(cached["forecast"], stale=True, local_date=local_today)
        raise WeatherError("Weather is unavailable. Check your connection and try again.") from error

    forecast["local_date"] = local_today
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = cache_path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"version": CACHE_VERSION, "key": key, "fetched_at": now(), "forecast": forecast}))
    os.chmod(temporary, 0o600)
    temporary.replace(cache_path)
    return forecast
