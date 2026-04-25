#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8076/v1}"
MODEL="${MODEL:-qwen3.6-vision}"
IMAGE_URL="${IMAGE_URL:-https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/640px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg}"

curl -sS "$BASE_URL/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(cat <<JSON
{
  \"model\": \"$MODEL\",
  \"messages\": [
    {
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"text\", \"text\": \"Describe this image in one short sentence.\"},
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"$IMAGE_URL\"}}
      ]
    }
  ],
  \"max_tokens\": 120
}
JSON
)"
