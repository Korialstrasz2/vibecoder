# AGENTS

## Screen Capture

When the user asks you to see their screen, take a screenshot, and says "take a screenshot" or similar:

1. Run: `powershell -ExecutionPolicy Bypass -File "scripts\capture-screenshot.ps1"`
2. The script outputs the path to the saved PNG in `screenshots/`
3. Read the image file with the Read tool to see what's on the user's screen

This works on Windows with no extra dependencies - it uses built-in .NET libraries.

## File Modification Backup Rule (MANDATORY)

**Before ANY file edit or write operation, you MUST create a backup:**

1. **Create session folder:** `\vibe-coding-portable\backup files - don't touch\auto_backups\<activity_name>_<YYYYMMDD>_<HHMM>\`
   - `<activity_name>`: Use the task name if provided, otherwise create a descriptive name (e.g., "fix_login_bug", "add_dark_mode")
   - `<YYYYMMDD>`: Today's date (e.g., 20260425)
   - `<HHMM>`: Current time in 24h format (e.g., 1430)

2. **Copy original file:** Copy the file you're about to modify into the session folder, preserving its original path structure relative to the project root.

3. **Then perform your edit/write** on the original file.

**Example:**
```
# Before editing D:\vibe-coding-portable-kit\vibe-coding-portable\config\settings.json
# Activity: "update_config" at 14:30 on 2026-04-25

powershell -Command "Copy-Item 'D:\vibe-coding-portable-kit\vibe-coding-portable\config\settings.json' 'D:\vibe-coding-portable-kit\vibe-coding-portable\backup files - don''t touch\auto_backups\update_config_20260425_1430\config\settings.json'"
```

**NEVER edit files inside `backup files - don't touch/` or any of its subfolders.**

## Project File Rules (STRICT)

- **NEVER create new files in the project root directory.** All new files must be created inside the `projects/` subfolder.
- **When creating a new project inside `projects/`:** Create a subfolder named `<project-name>_<YYYYMMDD>` (use today's date). If no project name is provided by the user, make up a fitting one. All project files go inside that subfolder.
