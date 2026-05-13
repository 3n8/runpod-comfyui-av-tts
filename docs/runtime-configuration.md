# Runtime Configuration

## RunPod

Set these in the RunPod endpoint or template environment variable GUI. Do not
commit real values to this repository and do not bake them into the image.

Required:

- `QWEN3_TTS_API_KEY`: private Qwen3-TTS API key.
- `QWEN3_TTS_BASE_URL`: base URL for the private Qwen3-TTS service.
- `QWEN3_TTS_VOICE_ID`: default voice ID, unless every request supplies
  `voice_id`.

Optional:

- `MAX_BASE64_VIDEO_MB`: maximum video size returned as base64. Default: `150`.
- `COMFYUI_ARGS`: extra ComfyUI CLI flags. Default: `--highvram`.
- `QWEN3_TTS_TIMEOUT`: TTS HTTP timeout in seconds. Default: `180`.

## Local docker-compose

For local handler/container testing, copy `.env.example` to `.env` and fill in
the same values. `docker-compose.yml` loads `.env` via `env_file`.

`.env` is ignored by git. `.env.example` is intentionally empty and safe to
commit.

Do not run LTX video generation locally on AMD hardware; use this path only for
lightweight handler/container checks.
