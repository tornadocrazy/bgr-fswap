# bgr-fswap — ReActor face swap + RMBG (BiRefNet) background removal only.
# No generation models. Trimmed from runpod-comfyui-flux-pulid (proven build).
FROM runpod/worker-comfyui:5.4.1-base

# ─────────────────────────────────────────────────────────────────────────────
# System packages
# ─────────────────────────────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip git && \
    rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# Python dependencies
# insightface pre-built wheel (avoids C compilation) + GPU onnxruntime.
# facexlib/gfpgan/timm/einops are needed by ReActor restore + RMBG.
# ─────────────────────────────────────────────────────────────────────────────
RUN pip install --no-cache-dir \
    https://huggingface.co/iwr-redmond/linux-wheels/resolve/main/insightface-0.7.3-cp312-cp312-linux_x86_64.whl \
    onnxruntime-gpu==1.20.0 \
    "transformers>=4.49.0" \
    facexlib \
    gfpgan \
    timm \
    einops

# ─────────────────────────────────────────────────────────────────────────────
# Custom nodes: ReActor (face swap) + RMBG (background removal).
# comfy-node-install pulls in CPU onnxruntime — force GPU build back afterwards.
# ─────────────────────────────────────────────────────────────────────────────
RUN comfy-node-install comfyui-reactor comfyui-rmbg && \
    pip uninstall -y onnxruntime && \
    pip install --no-cache-dir --force-reinstall onnxruntime-gpu==1.20.0

# Bypass ReActor NSFW filter (downloads a large classifier otherwise)
COPY reactor_sfw.py /comfyui/custom_nodes/comfyui-reactor/scripts/reactor_sfw.py

# Remove unused nodes to speed up startup (kills the ~18 comfy_api_nodes import
# failures: ideogram/openai/gemini/kling/etc. — none used here).
RUN rm -rf /comfyui/comfy_api_nodes

# Pre-generate matplotlib font cache so it isn't rebuilt (~0.8s) on every cold boot.
RUN python3 -c "from matplotlib.font_manager import FontManager; FontManager()" || true

# ─────────────────────────────────────────────────────────────────────────────
# Models — baked in (public sources, no token). Each in its own layer for caching.
# ─────────────────────────────────────────────────────────────────────────────

# InsightFace: buffalo_l (detect/recognize) + inswapper_128 (swap)
RUN     comfy model download \
        --url https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip \
        --relative-path models/insightface/models --filename buffalo_l.zip && \
    unzip /comfyui/models/insightface/models/buffalo_l.zip \
          -d /comfyui/models/insightface/models/buffalo_l && \
    rm /comfyui/models/insightface/models/buffalo_l.zip && \
    comfy model download \
        --url https://huggingface.co/ezioruan/inswapper_128.onnx/resolve/main/inswapper_128.onnx \
        --relative-path models/insightface --filename inswapper_128.onnx

# Face restore (GFPGAN) + face detection/parse weights.
# GFPGAN (used by ReActor) looks in models/facedetection/.
RUN     comfy model download \
        --url https://huggingface.co/gmk123/GFPGAN/resolve/main/GFPGANv1.4.pth \
        --relative-path models/facerestore_models --filename GFPGANv1.4.pth && \
    comfy model download \
        --url https://github.com/xinntao/facexlib/releases/download/v0.1.0/detection_Resnet50_Final.pth \
        --relative-path models/facexlib --filename detection_Resnet50_Final.pth && \
    mkdir -p /comfyui/models/facedetection && \
    cp /comfyui/models/facexlib/detection_Resnet50_Final.pth /comfyui/models/facedetection/ && \
    wget -q -O /comfyui/models/facedetection/parsing_parsenet.pth \
        "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/parsing_parsenet.pth"

# RMBG-2.0 (BiRefNet) background removal. Small text files via wget (chunked-
# transfer issue with the model downloader); weights via comfy model download.
RUN mkdir -p /comfyui/models/RMBG/RMBG-2.0 && \
    wget -q -O /comfyui/models/RMBG/RMBG-2.0/birefnet.py \
        "https://huggingface.co/1038lab/RMBG-2.0/raw/main/birefnet.py" && \
    wget -q -O /comfyui/models/RMBG/RMBG-2.0/BiRefNet_config.py \
        "https://huggingface.co/1038lab/RMBG-2.0/raw/main/BiRefNet_config.py" && \
    wget -q -O /comfyui/models/RMBG/RMBG-2.0/config.json \
        "https://huggingface.co/1038lab/RMBG-2.0/resolve/main/config.json"
RUN     comfy model download \
        --url https://huggingface.co/1038lab/RMBG-2.0/resolve/main/model.safetensors \
        --relative-path models/RMBG/RMBG-2.0 --filename model.safetensors
