#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Record bounded public-page evidence for import contract research.

"""Opt-in research probe; never an import crawler or production SSRF validator.

Example:
  python3 docs/import-fixtures/probe.py \
    --url 'https://www.example.org/recipe' --allow-host www.example.org
The public host must be approved explicitly. Redirects are not followed.
"""

import argparse
import hashlib
import ipaddress
import json
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


MAX_BYTES = 512_000
TIMEOUT_SECONDS = 15


class DenyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def validate_public_source(url: str, allowed_host: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("Only public HTTPS URLs are eligible for this probe.")
    if parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError("Credentials and nonstandard ports are not allowed.")
    if parsed.hostname.lower() != allowed_host.lower():
        raise ValueError("Pass the exact approved public hostname as --allow-host.")

    addresses = socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)
    if not addresses:
        raise ValueError("Hostname has no DNS records.")
    for record in addresses:
        address = ipaddress.ip_address(record[4][0])
        if not address.is_global:
            raise ValueError("DNS returned a nonpublic IP address.")

    return parsed.hostname


def probe(url: str, allow_host: str) -> dict:
    host = validate_public_source(url, allow_host)
    result = {
        "url": url,
        "hostname": host,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "environment": "Explicit opt-in, one GET; 15s; 512 KB limit; redirects disabled",
        "http_status": None,
        "mime_type": None,
        "response_bytes": None,
        "body_sha256": None,
        "html_structured_recipe_marker": False,
        "source_evidence_fetched_for_recipe": False,
        "structured_recipe_parsed": False,
        "native_end_to_end_tested": False,
        "limitations": "A source probe is not app import, schema.org Recipe parsing, backend queue, or native device acceptance.",
    }
    opener = urllib.request.build_opener(
        DenyRedirect(),
        urllib.request.ProxyHandler({}),
    )
    request = urllib.request.Request(
        url,
        headers={"Accept": "text/html", "User-Agent": "RecipePouch-contract-probe/1.0"},
    )

    try:
        with opener.open(request, timeout=TIMEOUT_SECONDS) as response:
            result["http_status"] = response.status
            result["mime_type"] = response.headers.get_content_type()
            body = response.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise ValueError(f"Body exceeds {MAX_BYTES} bytes")
    except urllib.error.HTTPError as error:
        result["http_status"] = error.code
        result["limitations"] += " HTTP error or redirect encountered; body not inspected."
        return result

    result["response_bytes"] = len(body)
    result["body_sha256"] = hashlib.sha256(body).hexdigest()
    if result["mime_type"] == "text/html":
        html = body.decode("utf-8", errors="replace")
        result["html_structured_recipe_marker"] = bool(
            re.search(r'"@type"\s*:\s*"?Recipe"?|schema\.org/Recipe', html, re.I)
        )
        result["source_evidence_fetched_for_recipe"] = True

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--allow-host", required=True, help="Exact explicitly approved public hostname")
    args = parser.parse_args()

    try:
        observation = probe(args.url, args.allow_host)
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(json.dumps({"error": str(error), "url": args.url}, ensure_ascii=False))
        return 1

    print(json.dumps(observation, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
