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


# Artist cards on /lineup. The 2027 site redesign renamed the classes with an "h27-" prefix
# and put `loading` before `src` on some images, so both spellings are accepted. Each card
# links the artist's page, carries their photo, name and (since 2027) the date they play.
CARD = re.compile(
    r'href="/artist/(?P<slug>[^"]+)".*?'
    r'<img[^>]*?\bsrc="(?P<img>https://cdn\.prod\.website-files\.com/[^"]+?\.(?:webp|jpg|jpeg|png))".*?'
    r'class="(?:h27-)?band-card-name[^"]*">(?P<name>[^<]+)<'
    r'(?:(?:(?!href="/artist/).)*?class="(?:h27-)?band-card-meta[^"]*">(?P<date>[^<]+)<)?',
    re.S)


def lineup_cards(body):
    """Every artist card on /lineup in document order, repeats included (the page lists
    the whole bill, then each day again): dicts of slug, name, image and date text."""
    return [{"slug": match.group("slug"),
             "name": clean(match.group("name")),
             "image": full_res(match.group("img")),
             "date": clean(match.group("date")) if match.group("date") else None}
            for match in CARD.finditer(body)]


def artist_details(page_slug, refresh=False):
    """Bio, Spotify ID and Instagram handle from an artist's own page."""
    try:
        body = page(f"/artist/{page_slug}", refresh=refresh)
    except Exception as error:                  # one missing page shouldn't stop the run
        print(f"  ! {page_slug}: {error}")
        return {}

    details = {}
    spotify = re.search(r"open\.spotify\.com/embed/artist/([A-Za-z0-9]+)", body)
    if spotify:
        details["spotifyArtistID"] = spotify.group(1)
    instagram = re.search(r"https://www\.instagram\.com/([A-Za-z0-9_.]+)/?", body)
    if instagram:
        details["instagram"] = instagram.group(1)

    # The bio sits between the "About" heading and the "Connect" social block.
    text = strip_tags(body)
    about = re.search(r"\bAbout\b(.*?)(?:\bConnect\b|Past Hinterlands)", text, re.S)
    if about:
        bio = re.sub(r'\s+([.,”"])', r"\1", about.group(1).strip())
        if 40 < len(bio) < 4000:
            details["bio"] = bio
    return details
