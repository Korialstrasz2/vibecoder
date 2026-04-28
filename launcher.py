import json
import re
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent
MAIN_DATA_DIR = ROOT / "MAIN_DATA"
MAIN_MODELS_DIR = MAIN_DATA_DIR / "models"
PROFILE_DIR = MAIN_DATA_DIR / "startup_bat_profiles"
PROFILE_REGISTRY: dict[tuple[str, int, str], dict] = {}

TARGET_COMMANDS = {
    "assistant_small": [ROOT / "ASSISTANT_SMALL" / "start_server.bat"],
    "connectors_server": [ROOT / "FILES_FOR_CONNECTORS" / "server files" / "start_server_main_pc.bat"],
    "main_plus_opencode": [
        MAIN_DATA_DIR / "start_server.bat",
        MAIN_DATA_DIR / "start_opencode.bat",
    ],
}

DENSE_RE = re.compile(r"(?i)(?<!x)(\d{1,3}(?:\.\d+)?)b")
MOE_RE = re.compile(r"(?i)([ae])(\d{1,3}(?:\.\d+)?)x(\d{1,3}(?:\.\d+)?)b")
ACTIVE_RE = re.compile(r"(?i)(?:^|[-_])a(\d{1,3}(?:\.\d+)?)b(?:$|[-_])")
ARCH_PATTERNS = ["qwen", "llama", "mistral", "mixtral", "deepseek", "gemma", "phi", "yi", "command-r", "gpt-oss"]


# Heuristic layer-count buckets for GGUF models where exact metadata isn't available.
DENSE_LAYER_BUCKETS = [(4, 32), (8, 36), (14, 40), (27, 48), (34, 60), (80, 80)]
MOE_LAYER_BUCKETS = [(8, 32), (16, 40), (32, 48), (64, 64), (120, 80)]


def run_bat_file(path: Path, args: list[str] | None = None) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    cmd = [str(path)]
    if args:
        cmd.extend(args)
    subprocess.Popen(cmd, cwd=str(path.parent), creationflags=subprocess.CREATE_NEW_CONSOLE)


# ── Shared log buffer for HTML monitoring ──
LAUNCH_LOGS: list[dict] = []
LAUNCH_LOGS_LOCK = threading.Lock()


def _launch_add_log(message: str, level: str = "info") -> None:
    """Append a log entry visible to the HTML monitor."""
    with LAUNCH_LOGS_LOCK:
        LAUNCH_LOGS.append({
            "timestamp": time.time(),
            "message": message,
            "level": level,
        })
    print(f"[LAUNCHER] [{level.upper()}] {message}", flush=True)


def _check_server_health(timeout: float = 3.0) -> bool:
    """Return True if llama-server is responding at http://127.0.0.1:8076/v1/models."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8076/v1/models", method="GET")
        urllib.request.urlopen(req, timeout=timeout)
        return True
    except urllib.error.HTTPError:
        # Server responded (e.g. 404) but IS running
        return True
    except Exception:
        return False


def _background_main_plus_opencode(script: Path, gpu_layers: int) -> None:
    """Run server startup polling + OpenCode launch in a background thread."""
    _launch_add_log(f"Launching server profile: {script.name} (GPU layers={gpu_layers})", "info")
    run_bat_file(script, args=[str(gpu_layers)])

    _launch_add_log("Waiting for llama-server to be ready at http://127.0.0.1:8076 ...", "info")

    max_attempts = 60      # 60 * 2s = 120s total
    server_ready = False

    for attempt in range(1, max_attempts + 1):
        time.sleep(2)
        if _check_server_health():
            _launch_add_log(f"llama-server is online! (ready after ~{attempt * 2}s)", "success")
            server_ready = True
            break
        if attempt % 5 == 0:
            _launch_add_log(f"Still waiting for server... ({attempt * 2}s elapsed)", "info")

    if server_ready:
        _launch_add_log("Server confirmed running. Launching OpenCode (--noninteractive)...", "info")
    else:
        _launch_add_log(
            f"TIMEOUT: Server not reachable after {max_attempts * 2}s. Launching OpenCode anyway (will need OpenRouter fallback).",
            "warn",
        )

    opencode_path = MAIN_DATA_DIR / "start_opencode.bat"
    run_bat_file(opencode_path, args=["--noninteractive"])
    _launch_add_log("OpenCode launcher dispatched.", "success")


def _format_gb(size_bytes: int) -> float:
    return round(size_bytes / (1024**3), 2)


def detect_gpus() -> list[dict]:
    try:
        res = subprocess.run(
            ["nvidia-smi", "--query-gpu=index,name,memory.total", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            check=True,
        )
        gpus = []
        for line in res.stdout.splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) != 3:
                continue
            idx, name, mem_mb = parts
            gpus.append({"index": idx, "name": name, "vram_gb": round(float(mem_mb) / 1024.0, 2)})
        return gpus
    except Exception:
        return []


def infer_architecture(filename_lower: str) -> str:
    for pattern in ARCH_PATTERNS:
        if pattern in filename_lower:
            return pattern
    return "unknown"


def parse_param_tag(filename: str) -> dict:
    lower = filename.lower()
    dense_match = DENSE_RE.search(lower)
    dense_count = float(dense_match.group(1)) if dense_match else None

    moe_match = MOE_RE.search(lower)
    if moe_match:
        family, experts_raw, active_raw = moe_match.groups()
        experts = float(experts_raw)
        active = float(active_raw)
        return {
            "param_tag": f"{family.upper()}{experts:g}x{active:g}B",
            "model_type": "moe",
            "active_params_b": active,
            "total_params_b": experts * active,
        }

    active_only_match = ACTIVE_RE.search(lower)
    if active_only_match and dense_count:
        active = float(active_only_match.group(1))
        return {
            "param_tag": f"{dense_count:g}B-A{active:g}B",
            "model_type": "moe",
            "active_params_b": active,
            "total_params_b": dense_count,
        }

    if dense_count:
        count = dense_count
        return {
            "param_tag": f"{count:g}B",
            "model_type": "dense",
            "active_params_b": count,
            "total_params_b": count,
        }

    return {"param_tag": "unknown", "model_type": "unknown", "active_params_b": None, "total_params_b": None}


def infer_layer_count(model: dict) -> int:
    if model.get("model_type") == "moe":
        params = model.get("total_params_b") or model.get("active_params_b") or 7
    else:
        params = model.get("active_params_b") or model.get("total_params_b") or 7
    buckets = MOE_LAYER_BUCKETS if model.get("model_type") == "moe" else DENSE_LAYER_BUCKETS
    for limit, layers in buckets:
        if params <= limit:
            return layers
    return buckets[-1][1]


def scan_models() -> list[dict]:
    if not MAIN_MODELS_DIR.exists():
        return []

    models = []
    for model_path in sorted(MAIN_MODELS_DIR.rglob("*.gguf")):
        if "mmproj" in model_path.name.lower():
            continue
        stats = model_path.stat()
        param_info = parse_param_tag(model_path.name)
        base = {
            "name": model_path.name,
            "path": model_path.relative_to(ROOT).as_posix(),
            "size_gb": _format_gb(stats.st_size),
            "architecture": infer_architecture(model_path.name.lower()),
            **param_info,
        }
        base["estimated_layers"] = infer_layer_count(base)
        models.append(base)
    return models


def choose_default_gpu(gpus: list[dict]) -> str:
    for gpu in gpus:
        if "4070" in gpu["name"].lower():
            return gpu["index"]
    return gpus[0]["index"] if gpus else "all"


def choose_default_model(models: list[dict]) -> str | None:
    if not models:
        return None
    for model in models:
        if "a3b" in model["name"].lower() or model["param_tag"].lower() == "a3x3b":
            return model["path"]
    return models[0]["path"]


def estimate_fit(models: list[dict], gpus: list[dict], model_path: str, context: int, gpu_selection: str) -> dict:
    model = next((m for m in models if m["path"] == model_path), None)
    if not model:
        raise ValueError("Selected model is unavailable")

    context_tokens = int(context)
    active_params_b = model.get("active_params_b") or model.get("total_params_b") or 7
    layer_count = model.get("estimated_layers") or infer_layer_count(model)

    if gpu_selection == "cpu" or not gpus:
        return {
            "recommended_gpu_layers": 0,
            "estimated_layer_count": layer_count,
            "estimated_fit": "cpu",
            "selected_vram_gb": 0.0,
            "kv_cache_gb": 0.0,
            "notes": "CPU mode selected or no GPUs detected",
        }

    if gpu_selection == "all":
        selected_gpus = gpus
    else:
        selected_gpus = [gpu for gpu in gpus if gpu["index"] == gpu_selection]
        if not selected_gpus:
            selected_gpus = gpus

    selected_vram = sum(gpu["vram_gb"] for gpu in selected_gpus)
    reserved = 1.25 * len(selected_gpus)

    # Heuristic estimation (GGUF + kv cache + runtime overhead).
    kv_cache_gb = round((context_tokens / 1024.0) * active_params_b * 0.007, 2)
    runtime_overhead_gb = 0.8
    usable_vram = max(selected_vram - reserved - kv_cache_gb - runtime_overhead_gb, 0.0)

    weights_need_gb = round(model["size_gb"] * 1.06, 2)
    offload_fraction = 0.0 if weights_need_gb <= 0 else max(min(usable_vram / weights_need_gb, 1.0), 0.0)

    recommended_layers = int(round(offload_fraction * layer_count))
    if selected_vram > 0 and recommended_layers == 0 and layer_count > 0:
        recommended_layers = 1
    recommended_layers = max(0, min(recommended_layers, layer_count))

    fit = "full" if offload_fraction >= 0.95 else "partial" if offload_fraction > 0 else "cpu_fallback"
    return {
        "recommended_gpu_layers": recommended_layers,
        "estimated_layer_count": layer_count,
        "estimated_fit": fit,
        "selected_vram_gb": round(selected_vram, 2),
        "usable_vram_gb": round(usable_vram, 2),
        "kv_cache_gb": kv_cache_gb,
        "weights_need_gb": weights_need_gb,
        "notes": f"Heuristic estimate based on model size, {active_params_b}B active params, and context {context_tokens}",
    }


def build_main_options() -> dict:
    global PROFILE_REGISTRY
    gpus = detect_gpus()
    models = scan_models()
    contexts = [16384, 32768, 65536, 131072]
    PROFILE_REGISTRY = regenerate_profile_scripts(models, gpus, contexts) if models else {}
    default_gpu = choose_default_gpu(gpus)
    return {
        "gpus": gpus,
        "models": models,
        "contexts": contexts,
        "gpu_choices": ([{"value": "cpu", "label": "CPU only"}, {"value": "all", "label": "All detected GPUs"}] + [
            {"value": gpu["index"], "label": f"GPU {gpu['index']} - {gpu['name']} ({gpu['vram_gb']} GB)"} for gpu in gpus
        ]),
        "defaults": {
            "context": 65536,
            "gpu_selection": default_gpu,
            "model_path": choose_default_model(models),
        },
        "generated_profiles": len(PROFILE_REGISTRY),
    }


def _profile_key(model_path: str, context: int, gpu_selection: str) -> tuple[str, int, str]:
    return (model_path, int(context), str(gpu_selection))


def build_profile_script(profile: dict, models: list[dict], gpus: list[dict]) -> tuple[Path, dict]:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    model_path = str(profile["model_path"])
    model_abs = (ROOT / Path(model_path)).resolve()
    if not model_abs.exists():
        raise FileNotFoundError(f"Selected model does not exist: {model_abs}")

    context = int(profile.get("context", 65536))
    gpu_selection = str(profile.get("gpu_selection", "all"))
    estimate = estimate_fit(models, gpus, model_path, context, gpu_selection)
    recommended_layers = int(estimate["recommended_gpu_layers"])
    max_layers = int(estimate["estimated_layer_count"])

    slug_model = re.sub(r"[^a-zA-Z0-9_-]", "_", Path(model_path).stem)[:40]
    slug_gpu = re.sub(r"[^a-zA-Z0-9_-]", "_", gpu_selection)
    script_path = PROFILE_DIR / f"start_profile_{slug_model}_{context}_{slug_gpu}.bat"

    lines = [
        "@echo off",
        "setlocal",
        "cd /d \"%~dp0..\"",
        f"set \"MODEL_FILE={model_abs}\"",
        f"set \"LLAMA_CTX={context}\"",
        "set \"CONTEXT_PROFILE=ui-profile\"",
        "set \"LLAMA_GPU_LAYERS=%~1\"",
        f"if \"%LLAMA_GPU_LAYERS%\"==\"\" set \"LLAMA_GPU_LAYERS={recommended_layers}\"",
    ]

    if gpu_selection == "cpu":
        lines.extend(["set \"CUDA_VISIBLE_DEVICES=\"", "set \"GGML_CUDA_DEVICE=\""])
    elif gpu_selection == "all":
        lines.extend(["set \"CUDA_VISIBLE_DEVICES=\"", "set \"GGML_CUDA_DEVICE=\""])
    else:
        lines.extend([f"set \"CUDA_VISIBLE_DEVICES={gpu_selection}\"", "set \"GGML_CUDA_DEVICE=0\""])

    lines.append(f"echo [PROFILE] LLAMA_GPU_LAYERS=%LLAMA_GPU_LAYERS% (recommended {recommended_layers}, max {max_layers})")
    lines.append('call "start_server.bat"')

    script_path.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    return script_path, {
        "recommended_gpu_layers": recommended_layers,
        "estimated_layer_count": max_layers,
    }


def regenerate_profile_scripts(models: list[dict], gpus: list[dict], contexts: list[int]) -> dict[tuple[str, int, str], dict]:
    if PROFILE_DIR.exists():
        shutil.rmtree(PROFILE_DIR)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    gpu_values = ["cpu", "all"] + [gpu["index"] for gpu in gpus]
    registry: dict[tuple[str, int, str], dict] = {}

    for model in models:
        for context in contexts:
            for gpu_selection in gpu_values:
                script_path, metadata = build_profile_script(
                    {"model_path": model["path"], "context": context, "gpu_selection": gpu_selection},
                    models=models,
                    gpus=gpus,
                )
                key = _profile_key(model["path"], context, gpu_selection)
                registry[key] = {"script_path": script_path, **metadata}

    return registry


def build_target_status() -> dict:
    status = {}
    for target, commands in TARGET_COMMANDS.items():
        missing = [str(command) for command in commands if not command.exists()]
        status[target] = {"ready": len(missing) == 0, "missing": missing, "commands": [str(command) for command in commands]}
    return status


class LauncherHandler(BaseHTTPRequestHandler):
    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_text(self, status: int, body: str, content_type: str) -> None:
        body_bytes = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        clean_path = urlparse(self.path).path

        if clean_path == "/health":
            self._write_json(200, {"status": "ok"})
            return
        if clean_path == "/targets":
            self._write_json(200, {"targets": build_target_status()})
            return
        if clean_path == "/main/options":
            self._write_json(200, build_main_options())
            return
        if clean_path in {"/", "/entrance.html"}:
            html = (ROOT / "entrance.html").read_text(encoding="utf-8")
            self._write_text(200, html, "text/html; charset=utf-8")
            return
        if clean_path == "/entrance.js":
            js = (ROOT / "entrance.js").read_text(encoding="utf-8")
            self._write_text(200, js, "application/javascript; charset=utf-8")
            return
        if clean_path == "/launch-log":
            parsed = urlparse(self.path)
            qs = parse_qs(parsed.query)
            since_str = qs.get("since", ["0"])[0]
            try:
                since = int(since_str)
            except (ValueError, TypeError):
                since = 0
            with LAUNCH_LOGS_LOCK:
                logs_since = LAUNCH_LOGS[since:]
                next_index = len(LAUNCH_LOGS)
            self._write_json(200, {"logs": logs_since, "next_index": next_index})
            return
        if clean_path == "/server-status":
            online = _check_server_health()
            self._write_json(200, {"online": online})
            return
        self._write_json(404, {"message": "Not found"})

    def do_POST(self):
        clean_path = urlparse(self.path).path
        if clean_path not in {"/start", "/main/estimate"}:
            self._write_json(404, {"message": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
            models = scan_models()
            gpus = detect_gpus()

            if clean_path == "/main/estimate":
                estimate = estimate_fit(
                    models=models,
                    gpus=gpus,
                    model_path=payload.get("model_path", ""),
                    context=int(payload.get("context", 65536)),
                    gpu_selection=str(payload.get("gpu_selection", "all")),
                )
                self._write_json(200, estimate)
                return

            target = payload.get("target")
            if target not in TARGET_COMMANDS:
                self._write_json(400, {"message": f"Unknown target: {target}"})
                return

            target_status = build_target_status()[target]
            if not target_status["ready"]:
                self._write_json(400, {"message": f"Cannot start {target}. Missing files found.", "missing": target_status["missing"]})
                return

            if target == "main_plus_opencode" and payload.get("profile"):
                global PROFILE_REGISTRY
                profile = payload["profile"]
                model_path = str(profile.get("model_path", ""))
                context = int(profile.get("context", 65536))
                gpu_selection = str(profile.get("gpu_selection", "all"))
                key = _profile_key(model_path, context, gpu_selection)

                if key not in PROFILE_REGISTRY:
                    PROFILE_REGISTRY = regenerate_profile_scripts(models, gpus, [16384, 32768, 65536, 131072])

                profile_entry = PROFILE_REGISTRY.get(key)
                if not profile_entry:
                    raise ValueError("Unable to find generated startup profile for selection")

                max_layers = int(profile_entry.get("estimated_layer_count", 0))
                force_999 = bool(profile.get("force_999", False))
                if force_999:
                    gpu_layers = 999
                else:
                    requested_layers = int(profile.get("gpu_layers", profile_entry.get("recommended_gpu_layers", 0)))
                    gpu_layers = max(0, min(requested_layers, max_layers))

                script = Path(profile_entry["script_path"])
                _launch_add_log(f"--- Starting Main + OpenCode ---", "info")
                _launch_add_log(f"Model: {model_path}", "info")
                _launch_add_log(f"Context: {context}", "info")
                _launch_add_log(f"GPU selection: {gpu_selection}", "info")
                _launch_add_log(f"GPU layers: {gpu_layers} (force_999={force_999})", "info")

                thread = threading.Thread(
                    target=_background_main_plus_opencode,
                    args=(script, gpu_layers),
                    daemon=True,
                )
                thread.start()

                self._write_json(
                    200,
                    {
                        "message": f"Server startup initiated with {script.name}. Monitoring progress...",
                        "status": "launching",
                        "profile": script.name,
                        "gpu_layers": gpu_layers,
                    },
                )
                return

            for command in TARGET_COMMANDS[target]:
                run_bat_file(command)
            self._write_json(200, {"message": f"Started: {target}"})
        except Exception as exc:  # noqa: BLE001
            self._write_json(500, {"message": str(exc)})


def main() -> None:
    server = HTTPServer(("127.0.0.1", 8765), LauncherHandler)
    print("Launcher running at http://127.0.0.1:8765")
    server.serve_forever()


if __name__ == "__main__":
    main()
