# open-url-new-window

Opens a URL in a new browser window (not a new tab in existing window) on macOS.

## When to Use

Use when the user asks to open a URL in a new browser window, or when you need to open documentation/references without disrupting their current browser session.

## Implementation

On macOS, use `open -na` with the browser's `--new-window` argument:

```bash
# For Vivaldi (default browser)
open -na "Vivaldi" --args --new-window "URL"

# For Chrome
open -na "Google Chrome" --args --new-window "URL"

# For Firefox
open -na "Firefox" --args --new-window "URL"

# For Safari (doesn't support --new-window, use -n for new instance)
open -n -a "Safari" "URL"
```

## Detecting Default Browser

```bash
defaults read ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null | grep -B1 "https" | grep "LSHandlerRoleAll" | head -1 | sed 's/.*= "\(.*\)";/\1/'
```

Common bundle IDs:
- `com.vivaldi.vivaldi` - Vivaldi
- `com.google.chrome` - Google Chrome
- `org.mozilla.firefox` - Firefox
- `com.apple.safari` - Safari
- `com.brave.browser` - Brave
- `com.microsoft.edgemac` - Microsoft Edge

## Universal Command

For Chromium-based browsers (Vivaldi, Chrome, Brave, Edge), this pattern works:

```bash
open -na "BROWSER_NAME" --args --new-window "URL"
```

## Notes

- The `-n` flag opens a new instance of the application
- The `-a` flag specifies the application name
- `--args` passes subsequent arguments to the application
- `--new-window` is a Chromium/Firefox flag, not an `open` command flag
- Safari doesn't support `--new-window`; use `-n` alone which may open a new instance
