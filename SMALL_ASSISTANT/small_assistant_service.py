from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import keyboard
import numpy as np
import requests
import sounddevice as sd


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class Decision:
    action: str
    response_text: str = ""
    tts: bool = False
    command_name: str = ""
    reason: str = ""


class SmallAssistantService:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.lock = threading.Lock()
        self.event_queue: queue.Queue[float] = queue.Queue()

    def run(self) -> None:
        hotkey = self.config.get("hotkey", "ctrl+windows+z")
        print(f"[INFO] Small assistant ready. Hotkey: {hotkey}")
        print("[INFO] Fully local flow: whisper.cpp -> local router -> local actions/TTS.")
        keyboard.add_hotkey(hotkey, lambda: self.event_queue.put(time.time()))

        while True:
            self.event_queue.get()
            if self.lock.locked():
                print("[WARN] Assistant is already processing a request.")
                continue
            threading.Thread(target=self._process_once, daemon=True).start()

    def _process_once(self) -> None:
        with self.lock:
            try:
                wav_path = self._record_audio()
                transcript = self._transcribe(wav_path)
                if not transcript:
                    print("[WARN] Empty transcript.")
                    return

                print(f"[USER] {transcript}")
                decision = self._route(transcript)
                self._handle_decision(decision)
            except Exception as exc:  # noqa: BLE001
                print(f"[ERROR] {exc}")

    def _record_audio(self) -> Path:
        seconds = int(self.config.get("listen_seconds", 5))
        sample_rate = int(self.config.get("sample_rate", 16000))
        channels = int(self.config.get("channels", 1))

        print(f"[INFO] Listening for {seconds}s...")
        audio = sd.rec(int(seconds * sample_rate), samplerate=sample_rate, channels=channels, dtype="int16")
        sd.wait()

        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav", dir=LOG_DIR) as tmp:
            wav_path = Path(tmp.name)

        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(np.asarray(audio).tobytes())

        print(f"[INFO] Audio captured: {wav_path}")
        return wav_path

    def _transcribe(self, wav_path: Path) -> str:
        stt = self.config["stt"]
        whisper_cli = Path(stt["whisper_cli_path"])
        model_path = Path(stt["model_path"])
        language = stt.get("language", "en")
        threads = str(stt.get("threads", 8))

        if not whisper_cli.exists():
            raise FileNotFoundError(f"whisper.cpp cli missing: {whisper_cli}")
        if not model_path.exists():
            raise FileNotFoundError(f"whisper.cpp model missing: {model_path}")

        out_prefix = wav_path.with_suffix("")
        cmd = [
            str(whisper_cli),
            "-m",
            str(model_path),
            "-f",
            str(wav_path),
            "-l",
            language,
            "-otxt",
            "-of",
            str(out_prefix),
            "-t",
            threads,
            "--no-timestamps",
        ]
        print(f"[CMD] {' '.join(cmd)}")
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            raise RuntimeError(f"whisper.cpp failed: {proc.stderr.strip() or proc.stdout.strip()}")

        txt_file = out_prefix.with_suffix(".txt")
        if not txt_file.exists():
            raise RuntimeError("whisper.cpp did not write transcript text output")

        return txt_file.read_text(encoding="utf-8", errors="ignore").strip()

    def _route(self, transcript: str) -> Decision:
        router = self.config["router"]
        url = router["base_url"].rstrip("/") + "/chat/completions"
        timeout = int(router.get("timeout_seconds", 45))

        system_prompt = (
            "You are a local command router. "
            "Return ONLY JSON with fields: action, response_text, tts, command_name, reason. "
            "Valid action values: answer, speak, execute, escalate. "
            "Choose execute only when command_name exists in the whitelist provided by the user app."
        )
        payload = {
            "model": router["model"],
            "temperature": 0.1,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": transcript},
            ],
            "response_format": {"type": "json_object"},
        }

        headers = {"Content-Type": "application/json"}
        api_key = router.get("api_key", "")
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.post(url, headers=headers, json=payload, timeout=timeout)
        response.raise_for_status()

        content = response.json()["choices"][0]["message"]["content"]
        data = self._safe_parse_json(content)
        return Decision(
            action=str(data.get("action", "answer")).strip().lower(),
            response_text=str(data.get("response_text", "")).strip(),
            tts=bool(data.get("tts", False)),
            command_name=str(data.get("command_name", "")).strip(),
            reason=str(data.get("reason", "")).strip(),
        )

    def _handle_decision(self, decision: Decision) -> None:
        print(f"[ROUTER] action={decision.action} command={decision.command_name} reason={decision.reason}")

        if decision.action == "execute":
            self._run_whitelisted_action(decision.command_name)
            if decision.response_text:
                print(f"[ASSISTANT] {decision.response_text}")
            if decision.tts:
                self._speak(decision.response_text or f"Executed {decision.command_name}")
            return

        if decision.action == "escalate":
            print("[INFO] Escalating to configured larger assistant target...")
            escalation_cmd = self.config.get("escalation", {}).get("command", "")
            if escalation_cmd:
                subprocess.Popen(escalation_cmd, shell=True, cwd=BASE_DIR)
            if decision.response_text:
                print(f"[ASSISTANT] {decision.response_text}")
            if decision.tts:
                self._speak(decision.response_text or "Escalating now")
            return

        text = decision.response_text or "Done."
        print(f"[ASSISTANT] {text}")
        if decision.action == "speak" or decision.tts:
            self._speak(text)

    def _run_whitelisted_action(self, action_name: str) -> None:
        actions = self.config.get("actions", {})
        action = actions.get(action_name)
        if not action:
            raise ValueError(f"Action is not whitelisted: {action_name}")

        command = action.get("command")
        if not command:
            raise ValueError(f"Whitelisted action missing command: {action_name}")

        print(f"[ACTION] {action_name}: {command}")
        subprocess.Popen(command, shell=True, cwd=BASE_DIR)

    def _speak(self, text: str) -> None:
        tts = self.config.get("tts", {})
        engine = tts.get("default_engine", "piper").lower()

        if engine == "piper":
            piper_exe = Path(tts.get("piper_exe", ""))
            piper_model = Path(tts.get("piper_model", ""))
            piper_config = Path(tts.get("piper_config", ""))

            if not piper_exe.exists() or not piper_model.exists():
                raise FileNotFoundError("Piper executable/model path is invalid")

            output_file = LOG_DIR / f"tts_{int(time.time())}.wav"
            cmd = [
                str(piper_exe),
                "--model",
                str(piper_model),
                "--output_file",
                str(output_file),
            ]
            if piper_config.exists():
                cmd.extend(["--config", str(piper_config)])

            proc = subprocess.run(cmd, input=text, text=True, capture_output=True, check=False)
            if proc.returncode != 0:
                raise RuntimeError(f"Piper failed: {proc.stderr.strip() or proc.stdout.strip()}")

            self._play_wav(output_file)
            return

        if engine == "sapi" and bool(tts.get("allow_sapi_fallback", False)):
            self._speak_with_sapi(text)
            return

        raise RuntimeError(f"Unsupported TTS engine or fallback disabled: {engine}")

    @staticmethod
    def _play_wav(path: Path) -> None:
        import winsound

        winsound.PlaySound(str(path), winsound.SND_FILENAME)

    @staticmethod
    def _speak_with_sapi(text: str) -> None:
        escaped = text.replace('"', "'")
        ps = (
            "Add-Type -AssemblyName System.Speech;"
            "$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            f'$s.Speak("{escaped}")'
        )
        subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=False)

    @staticmethod
    def _safe_parse_json(content: str) -> dict[str, Any]:
        content = content.strip()
        if content.startswith("{"):
            return json.loads(content)

        match = re.search(r"\{.*\}", content, flags=re.DOTALL)
        if not match:
            raise ValueError(f"Router did not return JSON: {content}")
        return json.loads(match.group(0))


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Missing config: {CONFIG_PATH}")
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


if __name__ == "__main__":
    os.chdir(BASE_DIR)
    cfg = load_config()
    service = SmallAssistantService(cfg)
    service.run()
