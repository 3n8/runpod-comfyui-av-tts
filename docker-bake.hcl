variable "DOCKERHUB_REPO" {
  default = "runpod"
}

variable "DOCKERHUB_IMG" {
  default = "worker-comfyui"
}

variable "RELEASE_VERSION" {
  default = "latest"
}

variable "COMFYUI_VERSION" {
  default = "latest"
}

# Global defaults for standard CUDA 12.6.3 images
variable "BASE_IMAGE" {
  default = "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
}

variable "CUDA_VERSION_FOR_COMFY" {
  default = "12.6"
}

variable "ENABLE_PYTORCH_UPGRADE" {
  default = "false"
}

variable "PYTORCH_INDEX_URL" {
  default = "https://download.pytorch.org/whl/cu126"
}

variable "PIN_PYTORCH_CUDA" {
  default = "true"
}

variable "PYTORCH_VERSION" {
  default = "2.9.1"
}

variable "TORCHVISION_VERSION" {
  default = "0.24.1"
}

variable "TORCHAUDIO_VERSION" {
  default = "2.9.1"
}

variable "MAX_TORCH_CUDA_VERSION" {
  default = "12.6"
}

variable "HUGGINGFACE_ACCESS_TOKEN" {
  default = ""
}

group "default" {
  targets = ["base", "ltx23-av-tts", "sdxl", "sd3", "flux1-schnell", "flux1-dev", "flux1-dev-fp8", "z-image-turbo"]
}

target "base" {
  context = "."
  dockerfile = "Dockerfile"
  target = "base"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "base"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-base"]
}

target "ltx23-av-tts" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "12.6"
    ENABLE_PYTORCH_UPGRADE = "false"
    PYTORCH_INDEX_URL = "https://download.pytorch.org/whl/cu126"
    PIN_PYTORCH_CUDA = "true"
    PYTORCH_VERSION = "2.9.1"
    TORCHVISION_VERSION = "0.24.1"
    TORCHAUDIO_VERSION = "2.9.1"
    MAX_TORCH_CUDA_VERSION = "12.6"
    MODEL_TYPE = "ltx23-av-tts"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-ltx23-av-tts"]
}

target "sdxl" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "sdxl"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-sdxl"]
  inherits = ["base"]
}

target "sd3" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "sd3"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-sd3"]
  inherits = ["base"]
}

target "flux1-schnell" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "flux1-schnell"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-schnell"]
  inherits = ["base"]
}

target "flux1-dev" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "flux1-dev"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-dev"]
  inherits = ["base"]
}

target "flux1-dev-fp8" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "flux1-dev-fp8"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-dev-fp8"]
  inherits = ["base"]
}

target "z-image-turbo" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    PIN_PYTORCH_CUDA = "${PIN_PYTORCH_CUDA}"
    PYTORCH_VERSION = "${PYTORCH_VERSION}"
    TORCHVISION_VERSION = "${TORCHVISION_VERSION}"
    TORCHAUDIO_VERSION = "${TORCHAUDIO_VERSION}"
    MAX_TORCH_CUDA_VERSION = "${MAX_TORCH_CUDA_VERSION}"
    MODEL_TYPE = "z-image-turbo"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-z-image-turbo"]
  inherits = ["base"]
}
