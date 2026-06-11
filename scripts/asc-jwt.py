#!/usr/bin/env python3
"""Mint a short-lived ES256 JWT for the App Store Connect API.

Usage: asc-jwt.py <key_id> <issuer_id> <p8_path>
Prints the token to stdout. Uses only stdlib + the openssl CLI.
"""
import base64
import json
import subprocess
import sys
import tempfile
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA-Sig-Value DER (SEQUENCE of two INTEGERs) -> 64-byte r||s."""
    assert der[0] == 0x30
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[idx] == 0x02
        ln = der[idx + 1]
        val = der[idx + 2 : idx + 2 + ln]
        out += val.lstrip(b"\x00").rjust(32, b"\x00")
        idx += 2 + ln
    return out


def main() -> None:
    key_id, issuer_id, p8_path = sys.argv[1:4]
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    with tempfile.NamedTemporaryFile(suffix=".bin") as msg:
        msg.write(signing_input.encode())
        msg.flush()
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", p8_path, msg.name],
            capture_output=True, check=True,
        ).stdout
    print(signing_input + "." + b64url(der_to_raw(der)))


if __name__ == "__main__":
    main()
