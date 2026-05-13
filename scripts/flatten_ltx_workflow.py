#!/usr/bin/env python3
"""Convert the saved LTX UI workflow with one subgraph into a ComfyUI API prompt.

This is intentionally narrow: it handles the April 30 LTX-2.3 AV workflow shape
and strips the old in-graph Qwen TTS node. The RunPod handler owns TTS now.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def widget_value(node: dict, input_name: str, widget_index: int):
    values = node.get("widgets_values", [])
    if isinstance(values, dict):
        return values.get(input_name)
    if widget_index < len(values):
        return values[widget_index]
    return None


def add_node(prompt: dict, node: dict, link_sources: dict[int, tuple[str, int]]):
    inputs = {}
    widget_index = 0
    for slot, input_def in enumerate(node.get("inputs", [])):
        name = input_def["name"]
        link_id = input_def.get("link")
        if link_id is not None:
            if link_id in link_sources:
                inputs[name] = [*link_sources[link_id]]
                if "widget" in input_def:
                    widget_index += 1
            elif "widget" in input_def:
                inputs[name] = widget_value(node, name, widget_index)
                widget_index += 1
            else:
                raise KeyError(f"missing source for link {link_id} on node {node['id']}")
        elif "widget" in input_def:
            inputs[name] = widget_value(node, name, widget_index)
            widget_index += 1

    prompt[str(node["id"])] = {
        "inputs": inputs,
        "class_type": node["type"],
        "_meta": {"title": node.get("title") or node["type"]},
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: flatten_ltx_workflow.py INPUT_UI_WORKFLOW OUTPUT_API_WORKFLOW", file=sys.stderr)
        return 64

    source_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    workflow = json.loads(source_path.read_text())
    subgraph = workflow["definitions"]["subgraphs"][0]

    top_nodes = {node["id"]: node for node in workflow["nodes"]}
    sub_nodes = {node["id"]: node for node in subgraph["nodes"]}

    top_links = {link[0]: link for link in workflow["links"]}
    sub_links = {link["id"]: link for link in subgraph["links"]}

    prompt: dict[str, dict] = {}

    # Keep only the runtime input/output nodes from the top-level graph.
    for node_id in (269, 345, 341):
        node = top_nodes[node_id]
        if node_id == 345:
            node = json.loads(json.dumps(node))
            node["widgets_values"]["audio_file"] = "input/runpod_qwen_tts.mp3"
            node["widgets_values"]["seek_seconds"] = 0
            node["widgets_values"]["duration"] = 0
        if node_id == 341:
            node = json.loads(json.dumps(node))
            node["widgets_values"] = ["video/comfyui_av_tts", "mp4", "h264"]

        link_sources = {
            link_id: (str(link[1]), link[2])
            for link_id, link in top_links.items()
            if link[3] == node_id
        }
        add_node(prompt, node, link_sources)

    external_input_sources = {
        0: ("269", 0),  # first frame image
        1: ("345", 0),  # loaded Qwen TTS audio
    }

    sub_link_sources: dict[int, tuple[str, int]] = {}
    for link_id, link in sub_links.items():
        origin_id = link["origin_id"]
        if origin_id == -10:
            source = external_input_sources.get(link["origin_slot"])
            if source is not None:
                sub_link_sources[link_id] = source
        else:
            sub_link_sources[link_id] = (str(origin_id), link["origin_slot"])

    for node_id in sorted(sub_nodes):
        node = sub_nodes[node_id]
        # The generated TTS audio is passed directly to CreateVideo and an empty
        # LTX audio latent is used for sampling. The old audio VAE encode/mask
        # path is intentionally excluded; that path caused the NestedTensor size
        # mismatch during the April 30 local tests.
        if node_id in (327, 328):
            continue
        add_node(prompt, node, sub_link_sources)

    # Top-level SaveVideo receives the CreateVideo output from the subgraph.
    prompt["341"]["inputs"]["video"] = ["312", 0]

    # Runtime injection points used by handler.py.
    prompt["269"]["inputs"]["image"] = "runpod_input.png"
    prompt["319"]["inputs"]["value"] = "__PROMPT__"
    prompt["323"]["inputs"]["value"] = 24
    prompt["330"]["inputs"]["value"] = 1280
    prompt["324"]["inputs"]["value"] = 720
    prompt["331"]["inputs"]["value"] = 3.0
    prompt["332"]["inputs"]["start_index"] = 0
    prompt["332"]["inputs"]["duration"] = ["331", 0]
    prompt["345"]["inputs"]["audio_file"] = "input/runpod_qwen_tts.mp3"

    output_path.write_text(json.dumps(prompt, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
