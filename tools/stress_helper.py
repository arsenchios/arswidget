#!/usr/bin/env python3
"""
Помощник для расстановки ударений через нейросеть.

Зачем отдельный инструмент: модель, особенно дешёвая, легко меняет слово,
теряет строки, переставляет их местами или ставит два ударения. Если такой
ответ вклеить в словарь как есть, приложение начнёт учить неправильному — а
заметить это будет некому. Поэтому здесь два шага: выгрузить список и
вклеить ответ с проверкой каждой строки.

Использование:

  1. Выгрузить слова, которым нужно ударение (файлами по 200 строк):
       python3 tools/stress_helper.py export

  2. Каждый файл скормить модели с таким заданием:

       Расставь ударение в каждом слове. Верни ровно те же слова в том же
       порядке, по одному в строке, ничего не добавляя и не убирая.
       Ударение обозначай знаком U+0301 сразу после ударной гласной,
       например: успі́х. В односложных словах ударение не ставь.

  3. Сложить ответы в файл и вклеить:
       python3 tools/stress_helper.py merge ответы.txt

Проверяется каждая строка: слово без знака ударения обязано совпасть с
исходным буква в букву, знак должен стоять ровно один и только после
гласной. Всё, что не прошло, не попадает в словарь и печатается списком.
"""
import json
import sys
import unicodedata
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PACK_PATH = REPO_ROOT / "ArsWidget" / "Resources" / "vocab-ukrainian.json"
STRESS_PATH = REPO_ROOT / "ArsWidget" / "Resources" / "vocab-stress.json"
EXPORT_DIR = REPO_ROOT / "tools" / "stress-export"

ACCENT = "́"
VOWELS = set("аеёиоуыэюяєіїАЕЁИОУЫЭЮЯЄІЇ")
BATCH_SIZE = 200


def strip_accent(text: str) -> str:
    return text.replace(ACCENT, "")


def needs_stress(word: str) -> bool:
    """Односложным ударение не нужно, ставить его там — только путать."""
    return sum(1 for ch in word if ch in VOWELS) > 1


def collect_words(side: str = "target") -> list:
    """Слова, которым нужно ударение.

    `target` — только украинские: ударение важнее всего там, где слово учат.
    `ru` — только русские. `both` — и те и другие.

    Порядок здесь и при вклейке обязан совпадать, поэтому режим один и тот же
    надо указывать на обоих шагах.
    """
    data = json.loads(PACK_PATH.read_text(encoding="utf-8"))
    fields = {"target": ("target",), "ru": ("ru",), "both": ("ru", "target")}[side]
    words = []
    seen = set()
    for item in data["words"]:
        for field in fields:
            value = item[field]
            if value in seen or not needs_stress(value):
                continue
            seen.add(value)
            words.append(value)
    return words


def command_export(side: str) -> int:
    words = collect_words(side)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    for old in EXPORT_DIR.glob("part-*.txt"):
        old.unlink()

    batches = [words[i:i + BATCH_SIZE] for i in range(0, len(words), BATCH_SIZE)]
    for index, batch in enumerate(batches, start=1):
        path = EXPORT_DIR / f"part-{index:02d}.txt"
        path.write_text("\n".join(batch) + "\n", encoding="utf-8")

    print(f"Слов, которым нужно ударение: {len(words)}")
    print(f"Записано файлов: {len(batches)} в {EXPORT_DIR.relative_to(REPO_ROOT)}")
    print("\nЗадание для модели (одно и то же для каждого файла):\n")
    print("  Расставь ударение в каждом слове. Верни ровно те же слова в том же")
    print("  порядке, по одному в строке, ничего не добавляя и не убирая.")
    print("  Ударение обозначай знаком U+0301 сразу после ударной гласной,")
    print("  например: успі́х. В односложных словах ударение не ставь.")
    return 0


def validate(original: str, answer: str):
    """Возвращает (ок, причина). Молча ничего не чинит."""
    answer = unicodedata.normalize("NFC", answer.strip())
    if not answer:
        return False, "пустая строка"
    bare = strip_accent(answer)
    if bare != original:
        return False, f"слово изменилось: ожидалось «{original}», пришло «{bare}»"
    count = answer.count(ACCENT)
    if count == 0:
        return False, "ударение не проставлено"
    if count > 1:
        return False, f"ударений {count}, должно быть одно"
    position = answer.index(ACCENT)
    if position == 0 or answer[position - 1] not in VOWELS:
        return False, "ударение стоит не после гласной"
    return True, ""


def command_merge(answer_path: Path, side: str) -> int:
    words = collect_words(side)
    answers = [line for line in answer_path.read_text(encoding="utf-8").splitlines() if line.strip()]

    if len(answers) != len(words):
        print(f"Строк в ответе {len(answers)}, а слов {len(words)} — порядок нарушен.")
        print("Вклеивать нельзя: строки перестанут соответствовать словам.")
        return 1

    accepted = {}
    rejected = []
    for original, answer in zip(words, answers):
        ok, reason = validate(original, answer)
        if ok:
            accepted[original] = unicodedata.normalize("NFC", answer.strip())
        else:
            rejected.append((original, answer.strip(), reason))

    STRESS_PATH.write_text(
        json.dumps({"stressed": accepted}, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    print(f"Принято: {len(accepted)} из {len(words)}")
    print(f"Записано: {STRESS_PATH.relative_to(REPO_ROOT)}")
    if rejected:
        print(f"\nОтклонено {len(rejected)} — эти слова останутся без ударения:")
        for original, answer, reason in rejected[:40]:
            print(f"  {original} -> {answer}  ({reason})")
        if len(rejected) > 40:
            print(f"  … и ещё {len(rejected) - 40}")
    return 0


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {"export", "merge"}:
        print(__doc__)
        return 1
    # Какие слова берём: только украинские (по умолчанию), только русские или все.
    side = "target"
    for candidate, name in (("--ru", "ru"), ("--all", "both"), ("--uk", "target")):
        if candidate in sys.argv:
            side = name

    if sys.argv[1] == "export":
        return command_export(side)

    files = [a for a in sys.argv[2:] if not a.startswith("--")]
    if not files:
        print("Укажите файл с ответом модели: python3 tools/stress_helper.py merge ответы.txt")
        return 1
    return command_merge(Path(files[0]), side)


if __name__ == "__main__":
    sys.exit(main())
