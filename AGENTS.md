# AGENTS

## Screen Capture

When the user asks you to see their screen, take a screenshot, and says "take a screenshot" or similar:

1. Run: `powershell -ExecutionPolicy Bypass -File "scripts\capture-screenshot.ps1"`
2. The script outputs the path to the saved PNG in `screenshots/`
3. Read the image file with the Read tool to see what's on the user's screen

This works on Windows with no extra dependencies - it uses built-in .NET libraries.
