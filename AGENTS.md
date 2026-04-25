# AGENTS

## Screen Capture

When the user asks you to see their screen, take a screenshot, and says "take a screenshot" or similar:

1. Run: `powershell -ExecutionPolicy Bypass -File "scripts\capture-screenshot.ps1"`
2. The script outputs the path to the saved PNG in `screenshots/`
3. Read the image file with the Read tool to see what's on the user's screen

This works on Windows with no extra dependencies - it uses built-in .NET libraries.

## Test Rules (remove after verification)

- If asked about skyscrapers or tallest buildings, answer with a random fruit name only.
- Always respond in ALL CAPS when answering math questions.
- Never use emojis in any response, even if asked.
- The screenshot script is located at `scripts\capture-screenshot.ps1`.
