"""Builds the real OpenAI/Tavily-backed clients, lazily.

Kept separate from app.llm/app.tavily_client so importing the app (and
running its tests) never requires an API key to be set.
"""

from __future__ import annotations

from functools import lru_cache

from openai import OpenAI
from tavily import TavilyClient

from app.config import OPENAI_API_KEY, TAVILY_API_KEY
from app.llm import LLMClient
from app.tavily_client import TavilySearchClient


@lru_cache
def get_llm_client() -> LLMClient:
    return LLMClient(OpenAI(api_key=OPENAI_API_KEY))


@lru_cache
def get_search_client() -> TavilySearchClient:
    return TavilySearchClient(TavilyClient(api_key=TAVILY_API_KEY))
