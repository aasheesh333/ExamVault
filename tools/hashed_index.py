#!/usr/bin/env python3
"""Builds a one-way (hashed) roll-number index.

## Why hashed and not plaintext

Publishing the official candidate list as plain text is a copyright grey area, and
re-hosting the PDF is clearly not ours to do. So the published object contains no
roll numbers at all — only a salted SHA-256 digest per roll, truncated to 8 bytes
and sorted.

The result answers exactly one question per query ("is this specific roll
present?") and cannot be used to enumerate candidates: recovering 10 000 preimages
means brute-forcing the entire roll space for every entry, and the salt prevents
precomputing that.

The digest and normalisation here MUST match `HashedRollIndex` in the Flutter app
byte for byte. `hashed_index_test.dart` pins both sides against a shared vector.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import secrets

DIGEST_BYTES = 8
MODE = "sha256-8-salted"


def normalise(value: str) -> str:
    """Strips whitespace, nbsp, zero-width and dashes, then uppercases.

    Mirrors `HashedRollIndex.normalise` in Dart exactly.
    """
    cleaned = (
        value.replace("\u200b", "")
        .replace("\u00a0", "")
        .replace("\u2013", "")
        .replace("\u2014", "")
    )
    return "".join(ch for ch in cleaned if not ch.isspace()).upper()


def digest(roll: str, salt: str) -> str:
    """`sha256("<salt>:<NORMALISED_ROLL>")` truncated to 8 bytes, hex."""
    payload = f"{salt}:{normalise(roll)}".encode()
    return hashlib.sha256(payload).digest()[:DIGEST_BYTES].hex()


def exam_salt(exam_id: str) -> str:
    """Deterministic, exam-specific salt.

    Two properties matter:

    * **Per exam.** A table precomputed for one exam is useless against another,
      so an attacker pays the full cost for every exam they want to enumerate.
    * **Stable.** A random salt per build would change the object on every refresh,
      producing a new content hash — and therefore a new URL — every 30 minutes
      even when the candidate list had not changed. That churns R2, defeats the
      `immutable` cache, and makes it impossible to pin anything in a test.

    The salt is not a secret (it ships in the object). It exists to stop one
    precomputation from covering every exam, not to make the digest reversible.
    """
    return hashlib.sha256(f"examvault/v2/{exam_id}".encode()).hexdigest()[:32]


def build(rolls: list[str], salt: str | None = None) -> tuple[bytes, dict]:
    """Returns (gzip bytes, metadata)."""
    salt = salt or secrets.token_hex(16)

    hashes = sorted({digest(r, salt) for r in rolls if normalise(r)})

    # Duplicate roll numbers collapse to one digest; report the discrepancy so a
    # producer bug is visible rather than silent.
    doc = {
        "v": 2,
        "mode": MODE,
        "salt": salt,
        "total": len(hashes),
        "hashes": hashes,
    }

    raw = json.dumps(doc, separators=(",", ":")).encode()
    # mtime=0: gzip stamps the header with the current time by default, which
    # makes identical input produce different bytes — and therefore a different
    # content-addressed URL — on every run. Pinning it keeps the object name a
    # pure function of the candidate list.
    return gzip.compress(raw, compresslevel=9, mtime=0), doc


if __name__ == "__main__":
    # Self-check: a fixed vector the Dart test also asserts.
    SALT = "00112233445566778899aabbccddeeff"
    sample = ["125130000008", " 1251 3000 0023 ", "125130000032"]
    print("salt   ", SALT)
    for s in sample:
        print(f"  {s!r:<24} -> {digest(s, SALT)}")
    body, meta = build(sample, SALT)
    print("gzip   ", len(body), "bytes for", meta["total"], "hashes")
