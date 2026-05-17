# Container Requirements

This worker is built for RunPod Serverless on NVIDIA GPUs. Do not test video
generation on the local AMD host.

The deployable image is the `ltx23-av-tts` Docker bake target. It is pinned to
`nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04`, asks ComfyUI for CUDA `12.6`,
pins ComfyUI to `v0.21.1`, explicitly installs `/comfyui/requirements.txt` into
the worker runtime venv, and force-reinstalls PyTorch CUDA 12.6 wheels after
ComfyUI installation. The Docker build fails if the selected PyTorch wheel
reports a CUDA runtime newer than 12.6, because RunPod A100 workers may expose
host driver capability `12060`.

The Dockerfile keeps layers cache-friendly:

- `base`: upstream-style ComfyUI install plus runtime Python requirements.
- `custom_nodes`: LTX/VideoHelperSuite clones and their requirements.
- `downloader`: large model files.
- `final`: handler, workflows, and startup scripts only.

This lets routine handler/workflow fixes rebuild without re-downloading the
large model layer.

## Runtime contract

The first supported request mode is AV/TTS:

- input image as base64
- TTS text
- optional visual prompt, otherwise TTS text is reused as the visual prompt
- Qwen3-TTS API key provided as `QWEN3_TTS_API_KEY`
- optional `QWEN3_TTS_BASE_URL`, `QWEN3_TTS_VOICE_ID`, `width`, `height`, `fps`, `seed`
- MP4 returned as base64 under `output.videos`

## Required model files

These are baked by the `ltx23-av-tts` Docker build target:

| Destination | Source |
| --- | --- |
| `/comfyui/models/checkpoints/LTX-2/ltx-2.3-22b-dev-fp8.safetensors` | `https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-dev-fp8.safetensors` |
| `/comfyui/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors` | `https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors` |
| `/comfyui/models/loras/ltx-2.3-22b-distilled-lora-384.safetensors` | `https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-lora-384.safetensors` |
| `/comfyui/models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors` | `https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors` |

Approximate model payload is 47 GB before Docker layer overhead. RunPod GitHub
build images have an 80 GB image size limit, so this is viable but close enough
that we should keep the image focused.

## Required node/runtime pieces

- ComfyUI `v0.21.1` with NVIDIA/PyTorch CUDA support.
- PyTorch `2.9.1`, torchvision `0.24.1`, and torchaudio `2.9.1` from the
  official `cu126` wheel index for compatibility with RunPod hosts whose
  driver reports CUDA capability `12060`.
- Official Lightricks `ComfyUI-LTXVideo` node pack and requirements.
- `ComfyUI-VideoHelperSuite` for `VHS_LoadAudio`.
- `ffmpeg` and `ffprobe` for audio/video IO and duration measurement.
- Python handler dependencies: `runpod`, `requests`, `websocket-client`.

## NVIDIA-specific choices

- Target 48 GB+ NVIDIA GPUs for the first useful test.
- Use the FP8 LTX-2.3 checkpoint to reduce VRAM and disk pressure.
- Keep the two-stage LTX workflow with latent/spatial upscaling via
  `ltx-2.3-spatial-upscaler-x2-1.1.safetensors`.
- Use tiled VAE decode from the patched workflow to reduce decode memory spikes.
- Set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` to reduce allocator
  fragmentation.
- Start ComfyUI with `--highvram` by default for the 48 GB target. Override
  `COMFYUI_ARGS` for smaller GPUs.
- Do not add a separate frame/video super-resolution stack yet; LTX latent
  upscaling is the simplest quality improvement already aligned with the model.

## Secrets policy

Do not bake secrets into the image or repo. Set these on the RunPod endpoint:

- `QWEN3_TTS_API_KEY`
- optional `QWEN3_TTS_BASE_URL`
- optional `QWEN3_TTS_VOICE_ID`
- `RUNPOD_API_KEY` only on the local client side, not inside the container

Before pushing publicly, run a secret scan and inspect Docker build context.
