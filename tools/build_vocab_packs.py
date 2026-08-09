#!/usr/bin/env python3
"""
Сборщик словарных наборов для вкладки «Слова».

Зачем: наполнять словарь вручную невозможно, а нейросеть для этого не нужна —
список бытовых слов один и тот же, и выдумывать его заново каждый раз значит
платить за генерацию и получать иногда несуществующие переводы.

Как устроено:
  1. Частотный список русских слов (по субтитрам фильмов) задаёт порядок и
     уровень сложности: чем чаще слово встречается в живой речи, тем раньше
     его стоит учить. Уровень — это просто позиция в списке.
  2. Двуязычный словарь даёт перевод. Для украинского это словарь Apertium,
     который ведут лингвисты.
  3. Результат проверяется и складывается в JSON рядом с приложением.

Запуск:
    python3 tools/build_vocab_packs.py

Источники (оба свободные):
  - hermitdave/FrequencyWords — CC-BY-SA 4.0, частоты по OpenSubtitles
  - apertium/apertium-rus-ukr — GPL, двуязычный словарь rus↔ukr
"""
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "ArsWidget" / "Resources"
CACHE_DIR = Path(os.environ.get("VOCAB_CACHE_DIR", "/tmp/vocab-build-cache"))

FREQUENCY_URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_50k.txt"
APERTIUM_RUS_UKR_URL = "https://raw.githubusercontent.com/apertium/apertium-rus-ukr/master/apertium-rus-ukr.rus-ukr.dix"

# Уровень по позиции русского слова в частотном списке. Границы примерно
# соответствуют тому, как считают объём словаря на A1/A2/B1/B2.
LEVELS = [(1000, "A1"), (3000, "A2"), (8000, "B1"), (20000, "B2")]

# Служебные части речи (предлоги, союзы, частицы) в карточках бесполезны:
# их не учат списком, они приходят с фразами.
MEANINGFUL_POS = {"n", "vblex", "adj", "adv", "np", "num"}

MAX_WORDS_PER_PACK = 2000


def fetch(url: str, filename: str) -> Path:
    """Скачивает файл один раз и кладёт в кеш, чтобы повторный запуск был мгновенным."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / filename
    if path.exists() and path.stat().st_size > 0:
        print(f"  из кеша: {filename}")
        return path
    print(f"  скачиваю: {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        path.write_bytes(response.read())
    return path


def load_frequency_ranks(path: Path) -> dict:
    """Слово -> его позиция в частотном списке (1 = самое частое)."""
    ranks = {}
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
        word = line.split(" ", 1)[0].strip().lower()
        if word and word not in ranks:
            ranks[word] = index + 1
    return ranks


def surface_form(node) -> str:
    """Само слово или выражение из <l>/<r>.

    Многословные выражения записаны через разделитель <b/>: «в самом деле».
    Читать только текст до первого потомка нельзя — получится «в», и к нему
    прицепится перевод всего выражения. Грамматические пометки <s/> идут
    после слова, на них разбор заканчивается.
    """
    parts = []
    if node.text:
        parts.append(node.text)
    for child in node:
        if child.tag == "s":
            break
        parts.append(" " if child.tag == "b" else (child.text or ""))
        if child.tail:
            parts.append(child.tail)
    return " ".join("".join(parts).split())


def load_apertium_pairs(path: Path) -> list:
    """Пары (русское, украинское, часть речи) из двуязычного словаря."""
    root = ET.parse(path).getroot()
    pairs = []
    for section in root.findall(".//section"):
        for entry in section.findall("e"):
            pair = entry.find("p")
            if pair is None:
                continue
            left, right = pair.find("l"), pair.find("r")
            if left is None or right is None:
                continue
            source = surface_form(left)
            target = surface_form(right)
            if not source or not target:
                continue
            tags = left.findall("s")
            pos = tags[0].get("n") if tags else None
            pairs.append((source, target, pos))
    return pairs


def level_for(rank: int):
    for limit, name in LEVELS:
        if rank < limit:
            return name
    return None


CYRILLIC = re.compile(r"^[а-яёіїєґА-ЯЁІЇЄҐ][а-яёіїєґА-ЯЁІЇЄҐ' -]*$")


def build_pack(pairs: list, ranks: dict, language: str) -> list:
    """Отбирает, чистит и раскладывает по уровням."""
    seen = set()
    words = []
    skipped = {"нет в частотном списке": 0, "служебное слово": 0,
               "перевод равен исходному": 0, "странные символы": 0, "дубль": 0}

    for source, target, pos in pairs:
        key = source.lower()

        if pos not in MEANINGFUL_POS:
            skipped["служебное слово"] += 1
            continue
        rank = ranks.get(key)
        if rank is None:
            skipped["нет в частотном списке"] += 1
            continue
        level = level_for(rank)
        if level is None:
            skipped["нет в частотном списке"] += 1
            continue
        # Карточка «причина -> причина» ничему не учит.
        if source.lower() == target.lower():
            skipped["перевод равен исходному"] += 1
            continue
        if not CYRILLIC.match(source) or not CYRILLIC.match(target):
            skipped["странные символы"] += 1
            continue
        if key in seen:
            skipped["дубль"] += 1
            continue

        seen.add(key)
        words.append({"ru": source, "target": target, "level": level, "rank": rank})

    words.sort(key=lambda item: item["rank"])
    words = words[:MAX_WORDS_PER_PACK]
    for item in words:
        item.pop("rank")

    print(f"\n  {language}: отобрано {len(words)} слов")
    for reason, count in skipped.items():
        print(f"    пропущено, {reason}: {count}")
    by_level = {}
    for item in words:
        by_level[item["level"]] = by_level.get(item["level"], 0) + 1
    print("    по уровням:", ", ".join(f"{k}: {v}" for k, v in sorted(by_level.items())))
    return words


def main() -> int:
    print("Загрузка источников…")
    frequency_path = fetch(FREQUENCY_URL, "ru_50k.txt")
    apertium_path = fetch(APERTIUM_RUS_UKR_URL, "rus-ukr.dix")

    ranks = load_frequency_ranks(frequency_path)
    print(f"  частотный список: {len(ranks)} русских слов")

    pairs = load_apertium_pairs(apertium_path)
    print(f"  словарь rus-ukr: {len(pairs)} пар")

    pack = build_pack(pairs, ranks, "украинский")
    if len(pack) < 200:
        print("\nСлишком мало слов — не записываю, источник наверняка изменился.")
        return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUTPUT_DIR / "vocab-ukrainian.json"
    payload = {
        "language": "ukrainian",
        "source": "apertium/apertium-rus-ukr (GPL) + hermitdave/FrequencyWords (CC-BY-SA 4.0)",
        "words": pack,
    }
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nЗаписано: {out.relative_to(REPO_ROOT)} ({out.stat().st_size // 1024} КБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
