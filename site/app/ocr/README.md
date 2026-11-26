# Invoice text reading (on the device)

Tesseract OCR, served with Waad so an invoice photo is read in the employee's own browser — nothing is sent anywhere.
Loaded only when someone reads an invoice (`app/src/receipts.js` → `ocrRead`).

- `tesseract.min.js`, `worker.min.js` — tesseract.js 5.1.1 (Apache-2.0)
- `tesseract-core-simd-lstm.wasm.js`, `tesseract-core-lstm.wasm.js` — tesseract.js-core 5.1.1 (Apache-2.0)
- `ara.traineddata.gz`, `eng.traineddata.gz` — @tesseract.js-data/ara and /eng 1.0.0, `4.0.0_best_int` models
