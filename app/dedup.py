"""Duplicate detection for job opportunities.

Two listings are the same opportunity if they agree on company, title, and
location once whitespace/case differences are ignored — see the grilling
session's R2/R3 decisions (dedup key = company+title+location, skip on
duplicate rather than refresh).
"""

from __future__ import annotations

DedupKey = tuple[str, str, str]


def dedup_key(company: str, title: str, location: str) -> DedupKey:
    return (_normalize(company), _normalize(title), _normalize(location))


def _normalize(value: str) -> str:
    return " ".join(value.strip().lower().split())
