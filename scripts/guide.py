#!/usr/bin/env python3
"""Scrape the festival guide into Data/info.json for the app's offline Info tab."""
import re, html, json, os, sys

from festival_source import page, slug

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "info.json")
REFRESH = "--refresh" in sys.argv


def rich_to_text(fragment):
    """Flatten Webflow rich text to plain text, keeping paragraph and list breaks."""
    text = re.sub(r"(?is)<figure.*?</figure>", "", fragment)     # drop inline images
    text = re.sub(r"(?is)<!--.*?-->", "", text)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p\s*>", "\n\n", text)
    text = re.sub(r"(?i)<li[^>]*>", "• ", text)
    text = re.sub(r"(?i)</li\s*>", "\n", text)
    text = re.sub(r"(?i)</(h[1-6]|ul|ol|div)\s*>", "\n\n", text)
    text = html.unescape(re.sub(r"(?s)<[^>]+>", "", text))
    text = text.replace("‍", "").replace("\xa0", " ")       # Webflow padding chars
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


src = page("/info", refresh=REFRESH)

# Every guide entry is a CMS item carrying its category, title and rich-text body.
ITEM = re.compile(
    r'data-search="cms-item-\d+".*?'
    r'(?:href="(?P<href>/info/[^"]+)".*?)?'
    r'fs-cmsfilter-field="category"[^>]*>(?P<category>[^<]*)<.*?'
    r'fs-cmsfilter-field="name"[^>]*>(?P<name>[^<]*)<.*?'
    r'fs-cmsfilter-field="content"[^>]*>(?P<content>.*?)</div>\s*</div>',
    re.S)

topics, seen = [], set()
for match in ITEM.finditer(src):
    title = html.unescape(match.group("name")).strip()
    body = rich_to_text(match.group("content"))
    key = title.lower()
    if not title or not body or key in seen:
        continue
    seen.add(key)

    topic = {
        "id": slug(title),
        "title": title,
        "category": html.unescape(match.group("category")).strip() or "General Info",
        "body": body,
    }
    if match.group("href"):
        topic["url"] = "https://www.hinterlandiowa.com" + match.group("href")
    links = re.findall(r'href="(https?://[^"]+)"', match.group("content"))
    if links:
        topic["links"] = sorted(set(links))[:4]
    topics.append(topic)

if not topics:
    sys.exit("No guide topics parsed — the info page markup probably changed.")

# Preserve the site's own ordering of categories.
order, grouped = [], {}
for topic in topics:
    grouped.setdefault(topic["category"], []).append(topic)
    if topic["category"] not in order:
        order.append(topic["category"])

data = {
    "version": 1,
    "categories": [
        {
            "id": slug(name),
            "name": name,
            "topics": [{k: v for k, v in t.items() if k != "category"} for t in grouped[name]],
        }
        for name in order
    ],
}

with open(OUT, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)

print(f"{OUT}: {len(topics)} topics in {len(order)} categories")
for category in data["categories"]:
    print(f'  {category["name"]:26} {len(category["topics"]):2}')
