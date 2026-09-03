# Skin Classifier Model Card

**Status:** Not yet trained. Placeholder for MobileNetV3-Large skin classifier.

---

## Overview

- **Architecture:** MobileNetV3-Large
- **Quantization:** TFLite INT8
- **Expected size:** ~5.5 MB
- **Input:** RGB image, resized to 224x224
- **Output:** Multi-label probability vector for ~11 classes + residual-Normal

## Training Data

- **SCIN:** Skin condition dataset (research terms apply)
- **AZH:** 6 classes verified (no explicit license -- caveat)
- **Total images:** TBD (dataset merge in progress)

## Risk Tier Thresholds

| Risk Tier | Probability | Triage Level |
|---|---|---|
| Normal | <0.4 | Routine |
| Suspicious | 0.4-0.7 | Urgent |
| High | >0.7 | Emergency |

## Known Limitations

- Thresholds require clinical validation
- Performance on dark skin tones TBD
- Performance under poor lighting TBD
- Open-set handling (non-skin images) needs testing

## Validation Metrics (To Be Filled)

- Confusion matrix
- Per-class precision/recall/F1
- Macro-averaged one-vs-rest AUC
- Balanced accuracy
- Condition breakdown: lighting, blur, occlusion

---

*This card will be updated after training is complete.*
