"""Builds a passage set from Project Gutenberg novels.

Usage: python3 -I build_corpus.py <tuned|heldout> <gutenberg_dir> <out.json>

Missing texts are downloaded into <gutenberg_dir>. Each book gives its three most intense
225-word windows (violence, death and romance words, the kind the default guardrails rejected)
and one random calm control. `moment` is the window, about 90 s of audio, the smart-save span;
`recap` is the 500 words ending with it, about 200 s, the recap span.

`tuned` is the set the prompts were tuned on (PR #84). `heldout` uses other books and another
seed and was never used for tuning. Keep it that way: add a new set rather than tuning on it.
"""
import json, os, random, re, sys, urllib.request

SETS = {
    "tuned": (7, {
        345: "Dracula", 84: "Frankenstein", 120: "Treasure Island", 1184: "The Count of Monte Cristo",
        2701: "Moby Dick", 1342: "Pride and Prejudice", 1661: "The Adventures of Sherlock Holmes",
        1260: "Jane Eyre", 2852: "The Hound of the Baskervilles", 36: "The War of the Worlds",
        2148: "The Works of Edgar Allan Poe, Volume 2", 768: "Wuthering Heights", 1399: "Anna Karenina",
        2554: "Crime and Punishment", 174: "The Picture of Dorian Gray",
        43: "The Strange Case of Dr Jekyll and Mr Hyde", 64317: "The Great Gatsby", 219: "Heart of Darkness",
        1257: "The Three Musketeers", 2591: "Grimms' Fairy Tales", 1727: "The Odyssey", 6130: "The Iliad",
        1952: "The Yellow Wallpaper", 5200: "Metamorphosis",
    }),
    "heldout": (11, {
        1400: "Great Expectations", 98: "A Tale of Two Cities", 730: "Oliver Twist",
        28054: "The Brothers Karamazov", 158: "Emma", 76: "Adventures of Huckleberry Finn",
        209: "The Turn of the Screw", 25344: "The Scarlet Letter", 160: "The Awakening",
        2097: "The Sign of the Four", 35: "The Time Machine", 5230: "The Invisible Man",
        541: "The Age of Innocence", 863: "The Mysterious Affair at Styles", 145: "Middlemarch",
        600: "Notes from the Underground", 829: "Gulliver's Travels", 215: "The Call of the Wild",
        1259: "Twenty Years After", 4217: "A Portrait of the Artist as a Young Man", 2814: "Dubliners",
        16328: "Beowulf", 11: "Alice's Adventures in Wonderland", 1695: "The Man Who Was Thursday",
    }),
}

KEYWORDS = re.compile(r"\b(blood\w*|kill\w*|murder\w*|dead|death|corpse|knife|sword|axe|stab\w*|throat|kiss\w*|bosom|lips|embrac\w*|naked|bed|suicide|poison\w*|wound\w*|scream\w*|beat\w*|whip\w*|gun|pistol|shot|cocaine|opium|drunk\w*|slew|slain|spear|flesh|struck|strangl\w*|shriek\w*|bite|bit|teeth|die|dying|hang\w*|torture\w*|rage|fury|passion\w*|desire)\b", re.I)
MOMENT, RECAP = 225, 500


def text(directory, book_id):
    path = os.path.join(directory, f"pg{book_id}.txt")
    if not os.path.exists(path):
        url = f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.txt"
        with urllib.request.urlopen(url, timeout=60) as response, open(path, "wb") as out:
            out.write(response.read())
    return open(path, encoding="utf-8", errors="ignore").read()


def main():
    name, directory, out = sys.argv[1], sys.argv[2], sys.argv[3]
    seed, titles = SETS[name]
    os.makedirs(directory, exist_ok=True)
    random.seed(seed)
    items = []
    for book_id, title in titles.items():
        raw = text(directory, book_id)
        start, end = raw.find("*** START"), raw.find("*** END")
        body = raw[raw.find("\n", start) + 1:end] if start >= 0 and end > start else raw
        body = re.sub(r"\[Illustration[^\]]*\]", " ", body).replace("_", "")
        words = body.split()
        first, last = int(len(words) * 0.06), int(len(words) * 0.97)
        scored = []
        for i in range(max(first, RECAP), last - MOMENT, 40):
            window = words[i:i + MOMENT]
            if sum(1 for w in window if w.isupper() and len(w) > 3) > 6:
                continue  # headings and tables
            scored.append((sum(1 for w in window if KEYWORDS.search(w)), i))
        scored.sort(reverse=True)
        chosen = []
        for score, i in scored:
            if all(abs(i - j) > RECAP for _, j in chosen):
                chosen.append((score, i))
            if len(chosen) == 3:
                break
        calm = [entry for entry in scored if entry[0] <= 1]
        control = random.choice(calm) if calm else None
        for k, (score, i) in enumerate(chosen + ([control] if control else [])):
            kind = "sensitive" if k < len(chosen) else "control"
            items.append({"id": f"{book_id}-{kind[0]}{k}", "book": title, "kind": kind, "score": score,
                          "moment": " ".join(words[i:i + MOMENT]),
                          "recap": " ".join(words[i + MOMENT - RECAP:i + MOMENT])})
    with open(out, "w") as handle:
        json.dump(items, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    print(len(items), "passages,", sum(1 for x in items if x["kind"] == "sensitive"), "sensitive")


if __name__ == "__main__":
    main()
