from __future__ import annotations

import os

from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
TAVILY_API_KEY = os.environ.get("TAVILY_API_KEY")
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./jobby.db")

# Preferences/search defaults, per the grilling session.
DEFAULT_SEARCH_LIMIT = 10
DEFAULT_FRESHNESS_DAYS = 14
HISTORY_PAGE_SIZE = 25
