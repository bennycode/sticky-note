# Sticky Note

A post-it note that lives on your macOS desktop, styled like the built-in widgets. Click into it and type.

macOS widgets (WidgetKit) can't take keyboard input, so this is a small borderless app window that sits at desktop level instead: behind your other windows, on every Space, with no Dock icon.

## Build

Requires the Xcode command line tools.

```sh
./build.sh
open "build/Sticky Note.app"
```

Move the app to `/Applications` if you want to keep it around.

## Usage

- **Type:** click anywhere in the note.
- **Move:** drag the strip along the top edge.
- **Resize:** drag any edge.
- **Checklist:** press <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>L</kbd> or right-click the top strip and choose "Show Checkboxes". Each line becomes an item, and markers like `- ` or `[x] ` are picked up.
  - <kbd>Return</kbd> starts a new item (splitting the current one at the caret).
  - <kbd>⌫</kbd> at the start of an item merges it into the one above, or removes it when empty.
  - <kbd>↑</kbd> <kbd>↓</kbd> move between items.
  - Checked items move into a collapsible "checked items" section at the bottom.
- **Options:** right-click the top strip for "Show/Hide Checkboxes", "Open at Login" and "Quit".
- **Quit:** <kbd>⌘</kbd> <kbd>Q</kbd> while the note is focused, or use the right-click menu.

Your note is saved as you type to `~/Library/Application Support/StickyNote/note.json`. Window position and size are remembered too.
