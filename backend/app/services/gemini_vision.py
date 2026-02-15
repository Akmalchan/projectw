# app/services/gemini_vision.py
from __future__ import annotations

import base64
import json
import os
from typing import Any, Dict, Optional

import httpx


class GeminiVision:
    def __init__(self) -> None:
        self.api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self.model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip() or "gemini-2.5-flash"

    def enabled(self) -> bool:
        return bool(self.api_key)

    async def parse_person_outfit(self, image_bytes: bytes, prompt: Optional[str] = None) -> Dict[str, Any]:
        if not self.enabled():
            raise RuntimeError("GEMINI_API_KEY is not set")

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
        params = {"key": self.api_key}

        instruction = (
            "Return JSON ONLY (no markdown, no backticks).\n"
            "Analyze the person's outfit in the image.\n"
            "Output schema:\n"
            "{\n"
            '  "outfit": {\n'
            '    "items": [\n'
            '      {"category":"outerwear|top|bottom|shoes|accessory","type":"string","colors":["string"],"pattern":null|string,"material":null|string}\n'
            "    ],\n"
            '    "style_tags": ["string"],\n'
            '    "overall_palette": ["string"],\n'
            '    "notes": "string"\n'
            "  }\n"
            "}\n"
            "Category must be one of the allowed values."
        )

        user_text = f"{instruction}\nUser prompt: {(prompt or '').strip()}"

        b64 = base64.b64encode(image_bytes).decode("utf-8")

        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": user_text},
                        {"inline_data": {"mime_type": "image/jpeg", "data": b64}},
                    ],
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "response_mime_type": "application/json",
            },
        }

        async with httpx.AsyncClient(timeout=45.0) as client:
            resp = await client.post(url, params=params, json=payload)
            resp.raise_for_status()
            data = resp.json()

        text = ""
        try:
            text = data["candidates"][0]["content"]["parts"][0].get("text", "") or ""
        except Exception:
            text = ""

        text = text.strip()
        if not text:
            raise RuntimeError("Gemini returned empty response")

        try:
            return json.loads(text)
        except Exception:
            # If model drifts, return raw so you can debug quickly
            return {"raw": text}
