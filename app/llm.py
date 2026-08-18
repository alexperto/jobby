"""Thin adapter over the OpenAI SDK's structured-output call.

Isolating this one method is what makes profilize/searcher testable without
touching the OpenAI SDK in tests — swap in a fake with the same `extract`
signature (see tests/test_profilize.py, tests/test_searcher.py).
"""

from __future__ import annotations

from typing import Protocol, TypeVar

from openai import OpenAI
from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)

DEFAULT_MODEL = "gpt-4o-mini"


class Extractor(Protocol):
    def extract(self, prompt: str, schema: type[T]) -> T: ...


class LLMClient:
    def __init__(self, client: OpenAI, model: str = DEFAULT_MODEL):
        self._client = client
        self._model = model

    def extract(self, prompt: str, schema: type[T]) -> T:
        completion = self._client.chat.completions.parse(
            model=self._model,
            messages=[{"role": "user", "content": prompt}],
            response_format=schema,
        )
        parsed = completion.choices[0].message.parsed
        if parsed is None:
            raise ValueError("Model did not return a parseable structured response")
        return parsed
