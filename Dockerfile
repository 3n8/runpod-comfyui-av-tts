# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu126
ARG PIN_PYTORCH_CUDA=true
ARG PYTORCH_VERSION=2.9.1
ARG TORCHVISION_VERSION=0.24.1
ARG TORCHAUDIO_VERSION=2.9.1
ARG MAX_TORCH_CUDA_VERSION=12.6

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
# NVIDIA memory allocator setting commonly used to reduce fragmentation on
# large video workflows.
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV UV_HTTP_TIMEOUT=300
ENV UV_HTTP_RETRIES=10
ENV MAX_TORCH_CUDA_VERSION=${MAX_TORCH_CUDA_VERSION}

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    openssh-server \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Pin PyTorch to CUDA 12.6 wheels. ComfyUI's installer may otherwise select a
# newer CUDA runtime than some RunPod A100 hosts can support.
RUN if [ "$PIN_PYTORCH_CUDA" = "true" ]; then \
      uv pip install --force-reinstall \
        torch==${PYTORCH_VERSION} \
        torchvision==${TORCHVISION_VERSION} \
        torchaudio==${TORCHAUDIO_VERSION} \
        --index-url ${PYTORCH_INDEX_URL}; \
    fi

# RunPod currently places some A100 workers on hosts exposing CUDA driver
# capability 12.6. Fail the image build if ComfyUI/pip selected a newer
# PyTorch CUDA runtime, because that would make the worker exit before it can
# process jobs.
RUN python -c "import os, sys, torch; max_cuda = os.environ.get('MAX_TORCH_CUDA_VERSION', '12.6'); torch_cuda = torch.version.cuda; parse = lambda value: tuple(int(part) for part in value.split('.')[:2]); sys.exit('PyTorch is not CUDA-enabled') if not torch_cuda else None; sys.exit(f'PyTorch CUDA {torch_cuda} is newer than allowed {max_cuda}; this image will not run on CUDA 12.6 RunPod hosts.') if parse(torch_cuda) > parse(max_cuda) else print(f'PyTorch CUDA {torch_cuda} is compatible with max {max_cuda}')"

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Install custom nodes needed by the bundled AV/TTS workflow.
# Current ComfyUI carries the LTX-2.3 core nodes, but keeping the official
# Lightricks node pack installed makes the image less fragile across workflow
# revisions. VideoHelperSuite provides VHS_LoadAudio for loading generated TTS.
RUN git clone --depth=1 https://github.com/Lightricks/ComfyUI-LTXVideo.git /comfyui/custom_nodes/ComfyUI-LTXVideo \
    && uv pip install -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
    && git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
    && uv pip install -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt

# Add application code and scripts
ADD src/start.sh src/network_volume.py handler.py test_input.json ./
RUN chmod +x /start.sh
COPY workflows /workflows

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
# Set default model type if none is provided
ARG MODEL_TYPE=ltx23-av-tts

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories upfront
RUN mkdir -p models/checkpoints models/vae models/unet models/clip models/text_encoders models/diffusion_models models/model_patches

# Download checkpoints/vae/unet/clip models to include in image based on model type
RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
      wget -q -O models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -q -O models/vae/sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
      wget -q -O models/vae/sdxl-vae-fp16-fix.safetensors https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "sd3" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-schnell" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-schnell.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-dev" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-dev-fp8" ]; then \
      wget -q -O models/checkpoints/flux1-dev-fp8.safetensors https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "ltx23-av-tts" ]; then \
      mkdir -p models/checkpoints/LTX-2 models/text_encoders models/loras models/latent_upscale_models && \
      wget -q -O models/checkpoints/LTX-2/ltx-2.3-22b-dev-fp8.safetensors https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-dev-fp8.safetensors && \
      wget -q -O models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors && \
      wget -q -O models/loras/ltx-2.3-22b-distilled-lora-384.safetensors https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-lora-384.safetensors && \
      wget -q -O models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "z-image-turbo" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/text_encoders/qwen_3_4b.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/diffusion_models/z_image_turbo_bf16.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union.safetensors https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors; \
    fi

# Stage 3: Final image
#
# Keep final as the downloader filesystem instead of copying /comfyui/models
# into a fresh base stage. The LTX target bakes roughly 47GB of models; copying
# that tree into another stage creates a second huge layer and makes RunPod's
# cache export slow enough to hit the 30 minute build timeout.
FROM downloader AS final
