# bgr-fswap

RunPod serverless **ComfyUI** worker: **face swap (ReActor)** + **background removal (RMBG / BiRefNet)**.
No generation models (FLUX/T5/etc.) — generation stays on Gemini. This worker only swaps the
user's face onto a generated image and/or cuts out the background.

Based on `runpod/worker-comfyui:5.4.1-base`, trimmed to two custom nodes
(`comfyui-reactor`, `comfyui-rmbg`). Derived from the proven `runpod-comfyui-flux-pulid` build.

## Models (baked into the image at build, public sources — no token needed)
- Face swap: `inswapper_128.onnx` (ezioruan/HF), `buffalo_l` (insightface GH release)
- Face restore: `GFPGANv1.4.pth` (gmk123/HF)
- Face detect/parse: `detection_Resnet50_Final` (facexlib GH), `parsing_parsenet` (CodeFormer GH)
- BG removal: `RMBG-2.0` / BiRefNet (1038lab/HF) → `models/RMBG/RMBG-2.0/`

Embedding keeps cold start to load-from-disk only (no runtime downloads).

## Build / deploy
Connect this repo to a RunPod serverless endpoint (GitHub source). No build secrets required.
Dockerfile path: `dockerfile`. VRAM footprint is small (~2–3 GB) — any tier works; start on
A4000 / RTX 2000 Ada (16 GB) for low cold-start + cost. Prewarm on page-load covers cold start.

## Request (worker-comfyui API)
worker-comfyui takes a ComfyUI **API-format workflow** + input images:
```json
{
  "input": {
    "workflow": { ... ComfyUI graph (API format) ... },
    "images": [
      { "name": "target.png", "image": "<base64 generated image>" },
      { "name": "source.png", "image": "<base64 user selfie>" }
    ]
  }
}
```
Build the graph in the deployed ComfyUI UI (LoadImage→ReActorFaceSwap→RMBG→SaveImage), set the
RMBG node `background = Alpha` for a transparent PNG, then **Save (API Format)** and send it as
`workflow`. Keep the finalized workflow JSON in the calling app's repo, not here.

Node values that matter: ReActor `swap_model: inswapper_128.onnx`, `face_restore_model:
GFPGANv1.4.pth`; RMBG `model: RMBG-2.0`.
