# AI harness

Measures smart-save naming and recaps on the real on-device model, outside the simulator. It compiles the app's own AI sources (`MomentNamingService`, `RecapService` and what they use) with `Harness.swift` into a macOS command-line tool, so it runs the shipping prompts, parsers and retries against the host Mac's model. A simulator uses the same model, so the harness measures the same thing much faster.

Use it before and after any prompt, parser or retry change (`docs/ios/ai.md`, "Measuring"), then confirm the in-app path with the E2E opt-in (`E2E_REAL_MODEL=1`, `e2e/README.md`).

## Needs

- macOS 27 with Apple Intelligence on (System Settings › Apple Intelligence & Siri), and Xcode's toolchain. The binary targets macOS 27 because the app's iOS 27 error handling compiles in.
- One run at a time. The model serves one request at a time, and a second harness or a simulator using the model rate-limits both and skews latency.

## Passage sets

`corpus/` holds two sets of 96 public-domain passages from Project Gutenberg, 4 per novel: the 3 most intense 225-word windows (violence, death and romance words, the kind the default guardrails rejected) and 1 random calm control. `moment` is the window, about 90 s of audio, the smart-save span. `recap` is the 500 words ending with it, about 200 s, the recap span.

- `tuned.json`: the 24 novels the PR #84 prompts were tuned on. Results here are in-sample.
- `heldout.json`: 24 other novels and another seed, never used for tuning. This is the number to quote. Don't tune on it: if a change needs new passages to tune with, add a new set.

`build_corpus.py` rebuilds either set from the Gutenberg texts (it downloads missing ones):

```sh
python3 -I tools/ai-harness/build_corpus.py heldout <scratch>/gutenberg <scratch>/heldout.json
```

## Run

From the repository root, measure a baseline and a candidate, then compare:

```sh
tools/ai-harness/measure.sh origin/main <evidence>/main
tools/ai-harness/measure.sh --worktree <evidence>/branch     # or a commit
python3 -I tools/ai-harness/summarize.py <evidence>/main <evidence>/branch
```

`measure.sh` exports the revision's `Pageless/` with `git archive`, builds it with `build.sh`, and runs both sets in both modes, about 20 minutes per revision. Each run directory gets `run.txt` (revision, macOS, toolchain, time) and one JSONL per set and mode: per passage the outcome, the name, note, quote, mood, categories and characters or the recap and headline, the error when it failed, the fallback name the app would show instead, and the seconds taken.

For a few passages, build once and pass ids:

```sh
tools/ai-harness/build.sh . <scratch>/harness
<scratch>/harness tools/ai-harness/corpus/heldout.json moment <scratch>/out.jsonl 1400-s0,541-s2
```

`Harness.swift` calls the services through either side of PR #84's API change (`build.sh` defines `PASSAGE_CONTEXT` when `AIPassageContext.swift` exists), so revisions from before it still build. A new source file the services need goes in `build.sh`'s list.

Keep run output outside Git, and link it from the PR.
