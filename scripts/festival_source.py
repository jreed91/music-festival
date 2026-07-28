#!/usr/bin/env python3
"""Fetch and cache pages from hinterlandiowa.com.

The site is a Webflow build that rejects default urllib user agents, so requests go out
with a browser UA. Pages are cached under scripts/.cache so re-running the pipeline
doesn't hammer the site.
"""
import os, re, html, time, unicodedata, urllib.request

BASE = "https://www.hinterlandiowa.com"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")


def page(path, refresh=False):
    """Return the HTML at `path` ("/lineup"), fetching and caching on first use."""
    os.makedirs(CACHE, exist_ok=True)
    name = path.strip("/").replace("/", "_") or "home"
    cached = os.path.join(CACHE, f"{name}.html")

    if refresh or not os.path.exists(cached) or os.path.getsize(cached) < 1000:
        request = urllib.request.Request(BASE + path, headers={"User-Agent": UA})
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8", errors="replace")
        with open(cached, "w", encoding="utf-8") as handle:
            handle.write(body)
        time.sleep(0.3)   # be a considerate scraper
        return body

    return open(cached, encoding="utf-8", errors="replace").read()


def clean(text):
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def strip_tags(fragment):
    fragment = re.sub(r"(?is)<(script|style|noscript)[^>]*>.*?</\1>", " ", fragment)
    return clean(re.sub(r"(?s)<[^>]+>", " ", fragment))


def slug(name):
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-zA-Z0-9]+", "-", ascii_name).strip("-").lower()


def full_res(url):
    """Webflow appends -p-500 etc. for responsive variants; we want the original."""
    return re.sub(r"-p-\d+(\.\w+)$", r"\1", url)
