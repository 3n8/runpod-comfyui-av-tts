import base64
import json
import os
import sys
import tempfile
import types
import unittest
from unittest.mock import MagicMock, patch

runpod_stub = types.ModuleType("runpod")
runpod_stub.serverless = types.SimpleNamespace(start=lambda *_args, **_kwargs: None)
utils_stub = types.ModuleType("runpod.serverless.utils")
utils_stub.rp_upload = types.SimpleNamespace(upload_image=lambda *_args, **_kwargs: None)
sys.modules.setdefault("runpod", runpod_stub)
sys.modules.setdefault("runpod.serverless", runpod_stub.serverless)
sys.modules.setdefault("runpod.serverless.utils", utils_stub)
websocket_stub = types.ModuleType("websocket")
websocket_stub.WebSocket = MagicMock
websocket_stub.WebSocketException = Exception
websocket_stub.WebSocketConnectionClosedException = Exception
websocket_stub.WebSocketTimeoutException = TimeoutError
websocket_stub.enableTrace = lambda *_args, **_kwargs: None
sys.modules.setdefault("websocket", websocket_stub)

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import handler


class TestHandlerInputValidation(unittest.TestCase):
    def test_valid_input_with_workflow_only(self):
        validated, error = handler.validate_input({"workflow": {"key": "value"}})

        self.assertIsNone(error)
        self.assertEqual(validated["workflow"], {"key": "value"})
        self.assertIsNone(validated["images"])
        self.assertFalse(validated["av_tts"])

    def test_valid_input_with_workflow_and_images(self):
        payload = {
            "workflow": {"key": "value"},
            "images": [{"name": "image1.png", "image": "base64string"}],
        }

        validated, error = handler.validate_input(payload)

        self.assertIsNone(error)
        self.assertEqual(validated["workflow"], payload["workflow"])
        self.assertEqual(validated["images"], payload["images"])

    def test_missing_workflow_for_normal_request(self):
        validated, error = handler.validate_input(
            {"images": [{"name": "image1.png", "image": "base64string"}]}
        )

        self.assertIsNone(validated)
        self.assertEqual(error, "Missing 'workflow' parameter")

    def test_av_tts_request_can_use_bundled_workflow(self):
        image_data = base64.b64encode(b"fake image").decode("utf-8")

        validated, error = handler.validate_input(
            {"image": image_data, "tts_text": "hello", "voice_id": "voice"}
        )

        self.assertIsNone(error)
        self.assertTrue(validated["av_tts"])
        self.assertEqual(validated["images"][0]["name"], "runpod_input.png")
        self.assertEqual(validated["tts_text"], "hello")

    def test_av_tts_request_requires_image(self):
        validated, error = handler.validate_input(
            {"tts_text": "hello", "voice_id": "voice"}
        )

        self.assertIsNone(validated)
        self.assertEqual(error, "AV/TTS requests require 'image' or 'images'")

    def test_invalid_images_structure(self):
        validated, error = handler.validate_input(
            {"workflow": {"key": "value"}, "images": [{"name": "image1.png"}]}
        )

        self.assertIsNone(validated)
        self.assertEqual(
            error, "'images' must be a list of objects with 'name' and 'image' keys"
        )

    def test_invalid_json_string_input(self):
        validated, error = handler.validate_input("invalid json")

        self.assertIsNone(validated)
        self.assertEqual(error, "Invalid JSON format in input")

    def test_valid_json_string_input(self):
        validated, error = handler.validate_input('{"workflow": {"key": "value"}}')

        self.assertIsNone(error)
        self.assertEqual(validated["workflow"], {"key": "value"})


class TestHandlerHelpers(unittest.TestCase):
    @patch("handler.requests.get")
    def test_check_server_up(self, mock_get):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        self.assertTrue(handler.check_server("http://127.0.0.1:8188", 1, 50))

    @patch("handler.requests.get")
    def test_check_server_down(self, mock_get):
        mock_get.side_effect = handler.requests.RequestException()

        self.assertFalse(handler.check_server("http://127.0.0.1:8188", 1, 50))

    @patch("handler.requests.post")
    def test_queue_workflow(self, mock_post):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"prompt_id": "123"}
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response

        result = handler.queue_workflow({"1": {"class_type": "Test"}}, "client")

        self.assertEqual(result, {"prompt_id": "123"})

    @patch("handler.requests.get")
    def test_get_history(self, mock_get):
        mock_response = MagicMock()
        mock_response.json.return_value = {"123": {"outputs": {}}}
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response

        self.assertEqual(handler.get_history("123"), {"123": {"outputs": {}}})

    @patch("handler.requests.post")
    def test_upload_images_successful(self, mock_post):
        mock_response = MagicMock()
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response
        image_data = base64.b64encode(b"Test Image Data").decode("utf-8")

        result = handler.upload_images([{"name": "test.png", "image": image_data}])

        self.assertEqual(result["status"], "success")

    @patch("handler.requests.post")
    def test_upload_images_failed(self, mock_post):
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = handler.requests.RequestException(
            "upload failed"
        )
        mock_post.return_value = mock_response
        image_data = base64.b64encode(b"Test Image Data").decode("utf-8")

        result = handler.upload_images([{"name": "test.png", "image": image_data}])

        self.assertEqual(result["status"], "error")

    def test_encode_video_size_limit(self):
        with patch.object(handler, "MAX_BASE64_VIDEO_MB", 0):
            with self.assertRaises(ValueError):
                handler.encode_output_file("video.mp4", b"x", "video")


class TestAvTtsWorkflow(unittest.TestCase):
    def test_prepare_av_tts_workflow_injects_runtime_values(self):
        template = {
            "269": {"inputs": {"image": "placeholder.png"}},
            "319": {"inputs": {"value": "__PROMPT__"}},
            "323": {"inputs": {"value": 24}},
            "330": {"inputs": {"value": 1280}},
            "324": {"inputs": {"value": 720}},
            "331": {"inputs": {"value": 3}},
            "332": {"inputs": {"start_index": 0}},
            "345": {"inputs": {"audio_file": "input/runpod_qwen_tts.mp3"}},
            "341": {"inputs": {"filename_prefix": "video/comfyui_av_tts"}},
            "314": {"inputs": {"text": "bad"}},
            "285": {"inputs": {"noise_seed": 1}},
            "286": {"inputs": {"noise_seed": 2}},
        }
        validated = {
            "images": [{"name": "input.png", "image": "base64"}],
            "tts_audio": base64.b64encode(b"mp3").decode("utf-8"),
            "tts_text": "spoken words",
            "voice_id": "voice",
            "prompt": "visual prompt",
            "negative_prompt": "negative",
            "width": 768,
            "height": 512,
            "fps": 24,
            "audio_start": 0.5,
            "duration_padding": 0.25,
            "max_duration": 5,
            "seed": 42,
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            template_path = os.path.join(tmpdir, "workflow.json")
            with open(template_path, "w") as f:
                json.dump(template, f)

            with patch.object(handler, "COMFY_INPUT_DIR", tmpdir), patch.object(
                handler, "AV_TTS_WORKFLOW_PATH", template_path
            ), patch.object(handler, "probe_audio_duration", return_value=3.0):
                workflow = handler.prepare_av_tts_workflow(validated, "job/123")

        self.assertEqual(workflow["269"]["inputs"]["image"], "input.png")
        self.assertEqual(workflow["319"]["inputs"]["value"], "visual prompt")
        self.assertEqual(workflow["323"]["inputs"]["value"], 24)
        self.assertEqual(workflow["330"]["inputs"]["value"], 768)
        self.assertEqual(workflow["324"]["inputs"]["value"], 512)
        self.assertEqual(workflow["331"]["inputs"]["value"], 3.25)
        self.assertEqual(workflow["332"]["inputs"]["start_index"], 0.5)
        self.assertTrue(
            workflow["345"]["inputs"]["audio_file"].startswith("input/job_123_")
        )
        self.assertEqual(workflow["314"]["inputs"]["text"], "negative")
        self.assertEqual(workflow["285"]["inputs"]["noise_seed"], 42)
        self.assertEqual(workflow["286"]["inputs"]["noise_seed"], 42)


if __name__ == "__main__":
    unittest.main()
