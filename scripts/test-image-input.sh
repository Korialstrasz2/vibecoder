#!/usr/bin/env bash
# test-image-input.sh
#
# Smoke test: sends a text + image request to the local llama.cpp server
# and checks that it returns a response (proving vision input works).
#
# Usage:
#   ./scripts/test-image-input.sh
#   ./scripts/test-image-input.sh --image path/to/image.png
#
# Environment variables:
#   LLAMA_HOST  - server host (default: 127.0.0.1)
#   LLAMA_PORT  - server port (default: 8080)
#   IMAGE_FILE  - path to image for test (default: ./models/test-image.png)

set -euo pipefail

LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
BASE_URL="http://${LLAMA_HOST}:${LLAMA_PORT}/v1"

IMAGE_FILE="${IMAGE_FILE:-./models/test-image.png}"

echo "=== Image Input Smoke Test ==="
echo "Server: ${BASE_URL}"

# Check server health
echo -n "Checking server health... "
HEALTH=$(curl -sf "${BASE_URL}/models" 2>/dev/null || true)
if [ -z "$HEALTH" ]; then
    echo "FAILED - server not reachable at ${BASE_URL}"
    echo "Start llama-server first:"
    echo "  ./scripts/run-llama-qwen36-vision.sh"
    exit 1
fi
echo "OK"

# Check if we have an image file
if [ ! -f "$IMAGE_FILE" ]; then
    echo ""
    echo "No test image found at: $IMAGE_FILE"
    echo "Creating a small test PNG (1x1 red pixel)..."
    mkdir -p "$(dirname "$IMAGE_FILE")"
    printf '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52' > "$IMAGE_FILE"
    printf '\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53' >> "$IMAGE_FILE"
    printf '\xDE\x00\x00\x00\x0C\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00' >> "$IMAGE_FILE"
    printf '\x00\x00\x03\x01\x01\x00\x18\xDD\x8D\xB4\x00\x00\x00\x00\x49' >> "$IMAGE_FILE"
    printf '\x45\x4E\x44\xAE\x42\x60\x82' >> "$IMAGE_FILE"
    echo "Created: $IMAGE_FILE"
fi

# Encode image as base64
IMAGE_B64=$(base64 -w 0 "$IMAGE_FILE" 2>/dev/null || base64 "$IMAGE_FILE")
IMAGE_TYPE="image/png"

# For PNG we can detect type, for JPEG detect JPEG header
FIRST_BYTES=$(xxd -l 2 -p "$IMAGE_FILE" 2>/dev/null || od -A n -t x1 -N 2 "$IMAGE_FILE" | tr -d ' ')
if [ "$FIRST_BYTES" = "ff d8" ] || [ "$FIRST_BYTES" = "ffd8" ]; then
    IMAGE_TYPE="image/jpeg"
fi

# Build the request payload
PAYLOAD=$(cat <<ENDPAYLOAD
{
  "model": "qwen36-vision",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "What is in this image? Describe it briefly."},
        {
          "type": "image_url",
          "image_url": {
            "url": "data:${IMAGE_TYPE};base64,${IMAGE_B64}"
          }
        }
      ]
    }
  ],
  "max_tokens": 200,
  "temperature": 0.7
}
ENDPAYLOAD
)

echo ""
echo "Sending vision request..."
echo "Model: qwen36-vision"
echo "Image: $IMAGE_FILE ($IMAGE_TYPE)"
echo ""

RESPONSE=$(curl -sf "${BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-no-key-required" \
    -d "$PAYLOAD" 2>&1 || true)

if [ -z "$RESPONSE" ]; then
    echo "FAILED - no response from server"
    echo ""
    echo "Possible causes:"
    echo "  1. Server not running (start with: ./scripts/run-llama-qwen36-vision.sh)"
    echo "  2. Model 'qwen36-vision' not registered - check --mmproj is loaded"
    echo "  3. Image format not supported - try PNG or JPEG"
    echo "  4. Model does not support vision - mmproj may be missing"
    exit 1
fi

echo "=== Response ==="
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""
echo "=== Test complete ==="
echo "If you see a response above, image input is working!"
echo ""
echo "Troubleshooting:"
echo "  - 'model not found' -> check model name in opencode.jsonc matches server"
echo "  - 'unsupported format' -> mmproj may not be loaded; verify --mmproj flag"
echo "  - 'modalities' error -> ensure opencode.jsonc has modalities for vision model"
