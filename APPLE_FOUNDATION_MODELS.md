# Apple Foundation Models Reference

Reference documentation for the on-device Apple Intelligence Foundation Models used in Ebooker.

## Model: SystemLanguageModel.default

### Overview
On-device language model from Apple's Foundation Models framework (FoundationModels). Part of Apple Intelligence, available in iOS 18+.

### Specifications

| Property | Value |
|----------|-------|
| **Parameters** | ~3 billion |
| **Context Window** | 4096 tokens (shared input/output budget) |
| **Architecture** | Optimized for Apple Silicon via KV-cache sharing, 2-bit quantization-aware training |
| **Processing** | Entirely on-device (no server calls, private) |
| **Latency** | Low (local inference) |

### Context Budget
⚠️ **Critical Constraint**: The 4096-token context limit is a **shared budget** for both input and output:
- Every token in your prompt/input reduces available tokens for the model's response
- If you use 3000 tokens for input, only ~1000 tokens remain for output
- Plan prompt sizes carefully to ensure adequate space for responses

Example:
```
Input prompt:    2500 tokens
Available output: 1596 tokens (4096 - 2500)
```

### Capabilities

**Text Generation & Processing:**
- Text generation (creative writing, summaries)
- Text understanding and comprehension
- Text classification
- Guided generation with structured output
- Constrained tool calling

**Input Modalities:**
- Text (multilingual)
- Images (multimodal understanding)

**Framework Features:**
- `@Generable` macro for structured output (enforces response format)
- `@Guide` annotation for fine-grained output constraints
- `LanguageModelSession` for async generation
- LoRA adapter fine-tuning support

### Device Requirements

**Minimum:**
- iOS 18+
- Apple Silicon: A17 Pro, M-series, or newer

**Eligible Devices:**
- iPhone 15 Pro / Pro Max and later
- iPad Pro (M1+) / iPad Air (M1+)
- Mac with M-series chip

### Availability Check

Always verify availability before use:

```swift
let model = SystemLanguageModel.default
guard model.isAvailable else {
    // Fall back to default behavior
    return
}
```

### Performance Characteristics

- On-device model **matches or surpasses comparably-sized open baselines** in benchmarks
- Competitive performance for a 3B-parameter model
- Optimized specifically for everyday AI tasks, not complex reasoning

### Usage in Ebooker

**MomentNamingService** uses `SystemLanguageModel.default` to:
1. Take audio transcripts from user-selected moments
2. Generate structured `MomentNameSuggestion` (name + note)
3. Provide AI-assisted moment bookmarking

**Prompt Budget Example (Moment Naming with 50s+50s Context Window):**
```
Input breakdown:
- Instructions: ~100 tokens
- Prompt preamble: ~30 tokens
- Audio transcript (100 seconds): ~400-600 tokens
- Book title: ~10 tokens
Total input: ~540-740 tokens

Available for output: 3356-3556 tokens
Expected output: ~70-110 tokens (5 words + 3-4 sentences)
Usage: 2-3% of output budget
Margin: Abundant room ✓
```

### Important Limitations

1. **Context is limited** — plan prompt sizes; don't send entire audiobooks
2. **No persistent memory** — each call is stateless
3. **No internet access** — entirely local processing
4. **Device-dependent** — only works on eligible Apple silicon
5. **iOS 18+ only** — not available on older OS versions
6. **No fine-tuning on-device** — LoRA adapters only

### References

- [Apple Machine Learning Research - Apple Intelligence Foundation Language Models](https://machinelearning.apple.com/research/apple-intelligence-foundation-language-models)
- [Apple Foundation Models Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)
- [Apple Foundation Models Framework Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Getting Started with Foundation Models](https://www.ottorinobruni.com/getting-started-with-apple-foundation-models-for-local-ai-in-swiftui/)

### Notes for Future Development

- **Token counting**: Consider implementing token-counting utility before sending large transcripts
- **Error handling**: Always handle `.modelUnavailable` gracefully with sensible fallbacks
- **Testing**: Test on actual devices; simulator may not reflect real-world performance
- **Transcripts**: Audio transcripts for longer audio may exceed safe input budget — consider truncation strategies
