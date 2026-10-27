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
- **Options:** right-click the top strip for "Open at Login" and "Quit".
- **Quit:** <kbd>⌘</kbd> <kbd>Q</kbd> while the note is focused, or use the right-click menu.

Your text is saved as you type to `~/Library/Application Support/StickyNote/note.txt`. Window position and size are remembered too.
