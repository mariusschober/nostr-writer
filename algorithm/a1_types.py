"""HWP-A1 primitives, invariants and lineage data types. No capture authentication, cryptography or UI.

All inference arithmetic is integer. Candidate source declarations are observations,
not human-authorship attestations. A caller-supplied admission policy is mandatory.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from collections import defaultdict
import json
from typing import Any, Iterable

VERSION = "HWP-A1"
Q = 1_000_000
MODES = ("keyboard", "touch", "ime")
FAMILIES = ("automation", "mixed", "simulation", "transcription")
SOURCES = ("candidate", "external", "injected", "unknown", "assisted")
WS = frozenset("\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000")
STOPS = frozenset(".!?\u3002\uff01\uff1f\n\r\u2028\u2029")
LIMITS = dict(events=200_000, scalars=50_000, lcs_cells=1_000_000,
              causes=4096, time=2**63-1, closure=4096)

class Invalid(ValueError):
    """Unsupported or inconsistent evidence; never an AI-writing accusation."""

def require(ok: bool, message: str) -> None:
    if not ok:
        raise Invalid(message)

def integer(x: Any, lo: int = 0, hi: int = 2**63-1) -> int:
    require(type(x) is int and lo <= x <= hi, "INTEGER_RANGE")
    return x

def text(x: Any) -> str:
    require(type(x) is str and len(x) <= LIMITS["scalars"], "TEXT_LIMIT")
    require(not any(0xD800 <= ord(c) <= 0xDFFF for c in x), "UNICODE_SURROGATE")
    return x

def exact_keys(x: Any, needed: set[str], optional: set[str] = frozenset()) -> None:
    require(type(x) is dict and needed <= x.keys() and x.keys() <= needed | optional,
            "SCHEMA_KEYS")

def loads(s: str) -> dict:
    def pairs(items):
        d = {}
        for k, v in items:
            require(k not in d, "DUPLICATE_KEY")
            d[k] = v
        return d
    try:
        return json.loads(s, object_pairs_hook=pairs,
                          parse_float=lambda _: (_ for _ in ()).throw(Invalid("FLOAT")),
                          parse_constant=lambda _: (_ for _ in ()).throw(Invalid("NONFINITE")))
    except (json.JSONDecodeError, RecursionError) as e:
        raise Invalid("JSON") from e

def ratio(n: int, d: int, cap: int = Q) -> int:
    return min(cap, max(0, n * Q // max(1, d)))

def quantile(xs: Iterable[int], numerator: int, denominator: int = 100) -> int:
    """Nearest-rank, empty -> zero. No interpolated quantiles."""
    a = sorted(xs)
    return a[max(0, (len(a)*numerator + denominator-1)//denominator - 1)] if a else 0

def mean(xs: list[int]) -> int:
    return sum(xs)//len(xs) if xs else 0

def logsize(n: int) -> int:
    return min(Q, (max(0, n)+1).bit_length()*Q//20)

def offsets(s: str) -> list[int]:
    out = [0]
    for c in s:
        out.append(out[-1] + len(c.encode("utf-8")))
    return out

def lcs_pairs(old: str, new: str) -> dict[int, int]:
    """Map new scalar offsets to retained old offsets. Tie: skip old first."""
    require((len(old)+1)*(len(new)+1) <= LIMITS["lcs_cells"], "LCS_LIMIT")
    d = [[0]*(len(new)+1) for _ in range(len(old)+1)]
    for i in range(len(old)-1, -1, -1):
        for j in range(len(new)-1, -1, -1):
            d[i][j] = 1+d[i+1][j+1] if old[i] == new[j] else max(d[i+1][j], d[i][j+1])
    pairs, i, j = {}, 0, 0
    while i < len(old) and j < len(new):
        if old[i] == new[j]:
            pairs[j] = i; i += 1; j += 1
        elif d[i+1][j] >= d[i][j+1]:
            i += 1
        else:
            j += 1
    return pairs

@dataclass(frozen=True)
class Atom:
    char: str
    root: int
    occurrence: int
    copied_from: int | None = None

@dataclass
class Root:
    char: str
    birth: int
    t: int
    mode: str
    epoch: int
    lane: int
    source: str
    causes: tuple[int, ...]
    parents: tuple[int, ...]

@dataclass
class Mutation:
    seq: int
    t: int
    op: str
    touched: set[int]
    created: set[int]
    removed: set[int]
    at: int
    size: int
    jump: int
    age: int
    before: str
    after: str
    boundary: int
    causes: tuple[int, ...]
    epoch: int

@dataclass
class Replay:
    document: str
    live: list[Atom]
    roots: list[Root]
    mutations: list[Mutation]
    inputs: dict[int, dict]
    releases: dict[int, int]
    language: str
    quantum: int
    session_id: str


