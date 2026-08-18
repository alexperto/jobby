"""Thin adapter over the Tavily SDK.

Same reasoning as app/llm.py: search_jobs is tested against this interface
with a fake, never against the real Tavily SDK.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from tavily import TavilyClient as _RawTavilyClient


@dataclass
class SearchResult:
    url: str
    title: str


class Searcher(Protocol):
    def search(
        self, query: str, max_results: int, days: int | None = None
    ) -> list[SearchResult]: ...
    def extract(self, url: str) -> str: ...


class TavilySearchClient:
    def __init__(self, client: _RawTavilyClient):
        self._client = client

    def search(
        self, query: str, max_results: int = 10, days: int | None = None
    ) -> list[SearchResult]:
        kwargs = {"query": query, "max_results": max_results}
        if days is not None:
            kwargs["days"] = days
        response = self._client.search(**kwargs)
        return [
            SearchResult(url=r["url"], title=r.get("title", ""))
            for r in response.get("results", [])
        ]

    def extract(self, url: str) -> str:
        response = self._client.extract(urls=[url])
        results = response.get("results", [])
        if not results:
            return ""
        return results[0].get("raw_content", "")
