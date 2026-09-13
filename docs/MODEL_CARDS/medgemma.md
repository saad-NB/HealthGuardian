# MedGemma Model Card

**Status:** Using pre-trained model from HuggingFace.

---

## Overview

- **Model:** MedGemma-1.5-4B-IT
- **Quantization:** Q4_K_M GGUF
- **Source:** https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF
- **Language model size:** ~2.32 GiB (2,489,894,976 bytes)
- **Vision projector size:** ~0.79 GiB (851,252,224 bytes)

## Usage in Sehat Nigraan

- **Role:** Tier 2 (optional enhancement)
- **Mode:** Text-only in production (mmproj evaluated and dropped)
- **Runtime:** fllama (wraps llama.cpp)
- **Max tokens:** dynamic (ADR-015) — summary completion `clamp(4096 − prompt − 384, 1024, 1536)`; chat completion `clamp(3072 − prompt − 192, 512, 1536)`; `finish_reason: "length"` triggers a summary retry-once at 1536 or a chat truncation note
- **Temperature:** 0.1
- **Context size:** 4096 summary / 3072 chat

## Input Format

Free-text patient history + structured Tier 1 findings (vitals, GCS, complaint probes, sepsis screen, burn answers, modifiers).

## Output Format

SOAP-formatted narrative (Subjective, Objective, Assessment, Plan).

## Constraints

- Can only ESCALATE Tier 1, never downgrade (max() merge rule)
- Output includes `requires_human_verification: true` field (enforced at schema level)
- Does not diagnose; does not replace professional medical judgment

## Known Limitations

- 4B parameter model -- limited reasoning depth for complex cases
- Text-only pathway -- cannot process clinical images directly
- Requires ~4 GB RAM on device
- First inference includes model load time (~30s on low-end devices)

## License

Model license per HuggingFace repository (Google MedGemma terms).

---

*This card reflects the pre-trained model. No fine-tuning has been performed.*
