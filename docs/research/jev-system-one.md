# Jev and TypeSafe System One research

**Research date:** 2026-09-19 (Europe/Bucharest)
**Scope:** Jev, TypeSafe AI's System One programming model, current public API surface, strengths, limitations, evidence quality, and implications for native Apple-platform products.
**Sources:** Primary sources only: TypeSafe's product site, documentation, official GitHub repositories, legal pages, and first-party evaluation site.

## Executive finding

Jev is TypeSafe AI's first public **System One model**: it accepts text or structured text state plus a set of predeclared questions, then returns constrained typed judgments and probability distributions instead of prose. TypeSafe positions it as a machine-facing semantic decision primitive: code owns control flow, arithmetic, policy, and side effects; Jev supplies bounded "common-sense" judgments where exact rules are brittle. The official API exposes three primitives: `Choice` (one value from a defined set), `Score` (position over ordered descriptive levels), and `Noul` (probability that a yes/no condition is true). Questions over the same state are evaluated independently and in parallel. [System One](https://docs.typesafe.ai/concepts/system-one), [Primitives](https://docs.typesafe.ai/primitives), [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)

That makes Jev potentially valuable for high-volume or latency-sensitive **classification, ranking, routing, semantic verification, confidence-gated escalation, and feature extraction from text**. It is not a replacement for a generative model, deterministic code, exact arithmetic, date logic, or a reasoning agent. Jev 1.13's own "jaggedness" documentation says it can be literal, struggles with numeric precision and counting, loses accuracy through indirection or irrelevant context, and cannot generate text. [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)

For a native iOS app, the likely production architecture is **app → product-owned backend → TypeSafe API**, not a TypeSafe key embedded in the app. This is an inference from two official facts: TypeSafe's supported SDKs are Python and JavaScript/TypeScript (with direct HTTP available from any language), and its own agent skill says web-app API credentials should remain server-side. A backend also creates the necessary policy boundary for redaction, consent, rate limiting, audit logging, retries, and fallback. [Client SDKs](https://docs.typesafe.ai/sdk), [official TypeSafe agent skill](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)

## Name and product disambiguation

- **TypeSafe AI** is the company and API provider. Its website and documentation use “TypeSafe” as the product/API name. [TypeSafe AI](https://typesafe.ai/), [documentation](https://docs.typesafe.ai/introduction)
- **System One models** is TypeSafe's name for its model class, inspired by the fast/intuitive “System 1” distinction in *Thinking, Fast and Slow*. It is a TypeSafe product term, not a claim that the model implements Kahneman's psychological theory. [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- **Jev** is TypeSafe's flagship and first public System One model. TypeSafe says the name refers to economist William Stanley Jevons and the Jevons paradox: lower-cost intelligence is expected to create more demand. [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- **`jev-latest`** is the moving stable alias. As reviewed, it points to `jev-1.13.0`; applications that tune thresholds should pin a version and log the versioned model ID because aliases move. [Models](https://docs.typesafe.ai/models)
- The **TypeSafe agent skill** shown in the invitation screenshot is an integration/design guide for coding agents. It tells an agent how to structure TypeSafe workflows and directs it to the live docs; it is not itself the Jev model or a local runtime. The official repository supports Claude Code installation and `npx skills add typesafe-ai/skills --skill typesafe-ai` for other agents. [official skills repository](https://github.com/typesafe-ai/skills), [skill source](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)

## What the model actually does

The public endpoint is `POST https://api.typesafe.ai/v1/systemone`. A request contains a required `state` (string, JSON object, or array), a model ID, and a map of typed questions; answers return under the caller's question IDs. [HTTP API reference](https://docs.typesafe.ai/api)

| Primitive | Best fit | Output |
| --- | --- | --- |
| `Choice` | Select one option from a closed set: category, route, candidate, handler | selected option, probability for every option, confidence |
| `Score` | Judge an ordered semantic dimension with described levels: relevance, severity, tone | continuous position over the levels, legend, per-level probabilities, confidence |
| `Noul` | Evaluate a clean yes/no condition where the probability is useful | probability of “yes” from 0 to 1; no separate confidence field |

Source: [Primitives](https://docs.typesafe.ai/primitives).

Important semantics:

- The caller defines the possible answer space in advance. Jev cannot return a `Choice` or `Score` label outside the schema. [Primitives](https://docs.typesafe.ai/primitives)
- Each question is evaluated against the same state independently; one answer is not hidden context for another. Related independent questions should be batched and composed in code. A second request is appropriate only when the first result is needed to fetch evidence or construct the next state/options. [Primitives](https://docs.typesafe.ai/primitives), [speculative fan-out](https://docs.typesafe.ai/patterns/fan-out)
- `confidence` for Choice and Score is derived from how concentrated the returned probability distribution is. It is not a guarantee that the answer is correct or permission to perform a consequential action. Noul exposes the yes probability directly; a value near `0.5` means yes and no are similarly probable, not “medium intensity.” [Confidence](https://docs.typesafe.ai/confidence), [official agent skill](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)
- TypeSafe explicitly recommends narrow judgments a knowledgeable person could make quickly, relevant structured state, deterministic composition in code, and thresholds evaluated on the product's own data. [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)

## Special capabilities with genuine product leverage

### 1. Many semantic judgments in one low-latency call

Questions sharing the same state run in parallel. This enables “speculative fan-out”: ask every bounded question the workflow might need, then have code use only the answers relevant to the selected branch. TypeSafe's official 13-question cookbook reports one batched call as 12.2× cheaper and 10.0× faster than 13 sequential calls on a document-dominated workload, while also noting that concurrent separate calls would narrow the latency difference but not the repeated-input token cost. This is a first-party case study, not an independent benchmark. [parallel-questions cookbook](https://docs.typesafe.ai/cookbooks/parallel_questions)

High-impact shape: one text artifact enters the system and several downstream features need relevance, safety, intent, tone, evidence quality, or routing signals. The state is transmitted once; typed signals become reusable application data.

### 2. Confidence-aware automation rather than forced yes/no output

Choice and Score return full distributions plus confidence, while Noul returns a probability. Code can define different paths for confident automation, cautious confirmation, and low-confidence human or reasoning-model review. TypeSafe recommends testing confidence/accuracy curves on product data instead of adopting demo thresholds. [Confidence](https://docs.typesafe.ai/confidence), [confidence-gated routing](https://docs.typesafe.ai/patterns/confidence-routing)

High-impact shape: mistakes have unequal costs and a fallback already exists. Jev can handle the obvious majority cheaply while uncertainty routes to the user, deterministic validation, or a stronger model.

### 3. Closed-set selection without free-form parsing

Because options are declared by code, the result cannot invent a tool, enum case, candidate ID, or unsupported route. This is particularly useful when code already has the valid candidates: select a function plus known arguments, rerank retrieved records, classify into a taxonomy, or choose a source span that code then copies verbatim. [function-calling cookbook](https://docs.typesafe.ai/cookbooks/function_calling), [pre-parsed value extraction](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook), [reranking cookbook](https://docs.typesafe.ai/cookbooks/rerank_typesafe)

High-impact shape: the application can enumerate the safe possibilities and needs semantic selection, not generation.

### 4. Semantic verification and guardrail layer around other AI

TypeSafe documents patterns for checking whether citations support a claim, whether retrieved passages contain prompt injection or contradict a query, and whether an LLM input/output has defined hazards. These are bounded judgments whose probabilities can route failures to review. [citation checks](https://docs.typesafe.ai/cookbooks/citation_check), [RAG passage classification](https://docs.typesafe.ai/cookbooks/classifying_rag_passages), [LLM guardrails](https://docs.typesafe.ai/cookbooks/llm_guardrails)

High-impact shape: a generative feature already exists, but its output needs a fast independent judge before user-visible or irreversible use.

### 5. Reusable semantic features

Multiple Score/Noul outputs can be retained as features, combined with explicit weights, filtered differently by user preferences, or fed to a conventional supervised model. Changing a weight need not rerun Jev when the underlying evidence and question meanings have not changed. [composite scoring](https://docs.typesafe.ai/patterns/composite-scoring), [AutoResearch feature discovery](https://docs.typesafe.ai/cookbooks/autoresearch_feature_discovery)

High-impact shape: a product wants personalization, ranking, or policy tuning while keeping individual semantic signals observable and testable.

## Current technical and commercial facts

As reviewed on 2026-09-19, TypeSafe lists `jev-1.13.0` at **$0.042 per million input tokens**, with output tokens free, a **64k-token request budget**, a separate **32k budget for state plus the longest question**, text-only input, and listed limits of **250,000 tokens/second and 1,200 requests/minute**. TypeSafe warns that rate limits are dynamic. `jev-latest` and `jev-preview` currently resolve to the same version. [Models](https://docs.typesafe.ai/models)

Text input may be a string, JSON object, or array. Images, audio, and video are not accepted; callers must transcribe or otherwise convert them first. English is the primary training language and current best-performing language; TypeSafe says other languages are supported unevenly and require workload-specific evaluation. [System One](https://docs.typesafe.ai/concepts/system-one), [Models](https://docs.typesafe.ai/models)

TypeSafe lists official Python and JavaScript/TypeScript SDKs; other platforms use the HTTP endpoint. The official SDKs provide typed request/response objects and default retry handling. [Client SDKs](https://docs.typesafe.ai/sdk), [HTTP API reference](https://docs.typesafe.ai/api)

## Limits and failure modes

TypeSafe's own documentation supplies unusually concrete limitations for Jev 1.13:

- **No generation:** Jev does not write replies, summaries, code, labels not already defined by the caller, or reasoning explanations. Use a generative model when novel text is required. [System One](https://docs.typesafe.ai/concepts/system-one), [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)
- **Not a calculator:** counting, arithmetic, numeric proximity, exact magnitude reconstruction from Score levels, and date/time comparison are unreliable. Extract bounded semantic components if useful, but calculate, count, parse, order, and reconcile in code. [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)
- **Literal and weak through indirection:** write exact conditions and point at relevant state fields. Split multi-hop interpretations into direct judgments and deterministic composition. [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)
- **Distracted by irrelevant state:** retrieve/filter first and send only what each question needs. The advertised context window is capacity, not a reason to transmit whole databases or long unrelated documents. [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13), [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)
- **Text-only and cloud-hosted:** audio, photos, and video require an upstream transformation, and the resulting text leaves the device when sent to TypeSafe. [Models](https://docs.typesafe.ai/models), [Privacy Policy](https://typesafe.ai/legal/privacy-policy)
- **Still fallible:** calibration is a group-level property; it does not guarantee an individual answer. Typed output guarantees the interface, not truth. Thresholds and question design must be validated on representative labeled cases. [System One](https://docs.typesafe.ai/concepts/system-one), [official agent skill](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)

### What “zero hallucinations” does and does not mean

TypeSafe's marketing says Jev “can't hallucinate” and advertises “zero hallucinations.” Its technical explanation narrows this to schema conformance: Jev returns only values from the caller-defined answer space and therefore cannot fabricate an out-of-schema tool name or enum value. TypeSafe also states that the plotted 0% figure is **not empirical**; it follows from guaranteed schema matching. This does **not** mean every in-schema choice, score, or probability is factually correct. The documentation explicitly says calibration does not guarantee individual correctness and the model has published failure modes. [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev), [System One](https://docs.typesafe.ai/concepts/system-one), [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)

## Evidence quality and vendor claims

### Verified from public contracts and first-party documentation

- The typed API shape, three primitives, response fields, state formats, endpoint, model IDs, listed price/limits, and text-only modality are documented public interfaces. [API](https://docs.typesafe.ai/api), [Primitives](https://docs.typesafe.ai/primitives), [Models](https://docs.typesafe.ai/models)
- Closed-set schema conformance follows from the exposed contract; correctness of the selected in-schema answer does not. [Primitives](https://docs.typesafe.ai/primitives)
- The official SDK and skill repositories are public and inspectable. [TypeSafe GitHub organization](https://github.com/typesafe-ai), [official skills repository](https://github.com/typesafe-ai/skills)

### Vendor-reported; not independently verified in this research

- TypeSafe reports typical queries around 100 ms, a 70–500 ms range in its launch comparison, and 40–200× speedups for comparable System One-shaped queries. [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one), [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- The home page claims 193.6× faster and 444.6× cheaper. TypeSafe's launch post says these figures come from its four workflow evaluations and are expected to be at the high end of real-world gains. The reference “labels” are the average outputs of two frontier models, not independently adjudicated ground truth, and TypeSafe acknowledges possible bias because its own model-capabilities team created the workflows. [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev), [workflow evaluation site](https://evals.typesafe.ai/)
- TypeSafe says Jev achieves comparable intelligence to existing LLMs on System One tasks and uses a new architecture, parallel sampler, and training method called Reinforcement Learning for Calibrated Decisions (RLCD). No peer-reviewed architecture or training paper was found in the official source set reviewed here, so these remain first-party technical claims. [launch announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev)

No live Jev call, latency benchmark, calibration study, or domain accuracy evaluation was performed for this report. Access to the console invitation does not by itself validate TypeSafe's performance claims.

## Privacy and Apple-platform integration implications

TypeSafe says customer requests/responses are not used to train Jev and that the same weights serve every account; the public privacy policy says prompts and other input are collected to provide the service but are not used to train or fine-tune models. The policy allows processing for service operation/improvement and disclosures to service providers, says ordinary personal data is retained as reasonably necessary, and says the service is hosted in the United States. TypeSafe separately advertises zero-data-retention for enterprise customers, which means ordinary early-access use must not be assumed to be ZDR. [Models](https://docs.typesafe.ai/models), [Legal](https://docs.typesafe.ai/legal), [Privacy Policy](https://typesafe.ai/legal/privacy-policy)

Practical consequence for Unpaged or Parta: do not send audiobook text, transcripts, receipt contents, personal messages, identities, financial records, or other user data merely because a Jev feature is attractive. A production proposal first needs a data inventory, minimization/redaction design, user-facing disclosure/consent analysis, retention and regional-transfer review, and the repository's own external privacy-document update process. This paragraph is an architectural/legal-risk inference, not a claim from TypeSafe.

Minimum technical guardrails for a prototype:

1. Keep the TypeSafe API key off-device and out of the public repositories; call through a narrow product-owned backend.
2. Send synthetic or explicitly approved test data first.
3. Pin the model version during evaluation and log the version, question-set version, answers, confidence/probabilities, latency, and fallback outcome without logging sensitive state.
4. Build a labeled evaluation set from the actual domain. Compare Jev with deterministic baselines and the current feature, not only with a large LLM.
5. Define per-action confidence/probability thresholds and an explicit unavailable/timeout/429 fallback. Never treat low confidence as success.
6. Keep exact accounting, authorization, entitlements, reconciliation, dates, numeric thresholds, database writes, and irreversible actions in code.

## Best first proof-of-value shape

A strong Jev pilot is a **read-only semantic assistant** over non-sensitive or synthetic text that already has enumerated outcomes and an obvious fallback. It should batch several independent questions, expose uncertainty, and measure accuracy plus latency/cost against labeled examples. It should not begin with a write path, a hidden safety decision, private user content, or a feature requiring Jev to generate prose.

The pilot's acceptance evidence should include:

- a frozen model version and versioned question definitions;
- representative labeled cases, including ambiguous, adversarial, long, irrelevant-context, multilingual, and service-failure cases;
- accuracy and calibration by confidence bucket, not only overall accuracy;
- false-positive/false-negative costs tied to product behavior;
- end-to-end p50/p95 latency and actual token cost from the intended deployment region;
- a comparison with simple rules and the existing workflow;
- proof that every low-confidence, malformed, timeout, rate-limit, or unavailable result fails safely.

## Primary source index

- [TypeSafe AI home page](https://typesafe.ai/)
- [Introducing System One Models & Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- [Documentation index](https://docs.typesafe.ai/llms.txt)
- [Introduction](https://docs.typesafe.ai/introduction)
- [System One](https://docs.typesafe.ai/concepts/system-one)
- [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)
- [Primitives](https://docs.typesafe.ai/primitives)
- [Confidence](https://docs.typesafe.ai/confidence)
- [Models](https://docs.typesafe.ai/models)
- [HTTP API reference](https://docs.typesafe.ai/api)
- [Client SDKs](https://docs.typesafe.ai/sdk)
- [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)
- [Workflow evaluations](https://evals.typesafe.ai/)
- [Parallel questions cookbook](https://docs.typesafe.ai/cookbooks/parallel_questions)
- [Official TypeSafe GitHub organization](https://github.com/typesafe-ai)
- [Official TypeSafe agent skill](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)
- [Legal overview](https://docs.typesafe.ai/legal)
- [Privacy Policy](https://typesafe.ai/legal/privacy-policy)
