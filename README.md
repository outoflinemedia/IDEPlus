# IDEPlus

A native macOS text and code editor with FTP editing. AppKit, no dependencies, builds with only the Xcode Command Line Tools.

## Build and run

```bash
./build.sh
open build/IDEPlus.app
```

To install it, copy `build/IDEPlus.app` into `/Applications`. You can also open files from the command line: `build/IDEPlus.app/Contents/MacOS/IDEPlus file1 file2`.

## Editing files on your FTP server

1. File > FTP Sites… (Cmd-Shift-F): click +, fill in host, username, password and start folder (for example `public_html`). "Use FTPS" encrypts the connection; if the certificate is for your host's server name instead of your domain, either type that server name as the host or tick "Allow certificate name mismatch". Test Connection checks it.
2. In the directory window, switch to the **FTP** tab (or File > Open from FTP…, Ctrl-Cmd-O), pick the site and click Connect.
3. Double-click a file to open it. **Every Save uploads it back**; the status bar shows "✓ Uploaded … at time". If an upload fails the tab keeps its `*` and shows ⚠︎, and you're offered Try Again.
4. Right-click in the FTP tree for New File, New Folder, Rename, Delete, Refresh. File > Reload from Disk re-downloads the server's copy.
5. **Favorites:** below the FTP tree, group the files you're working on into projects, from any of your sites. Right-click files in the FTP list > Add to Project (or drag them onto a project), or click the star on an FTP tab. Double-click a favorite to open it (IDEPlus connects to its site first). See [docs/favorites-plan.md](docs/favorites-plan.md).

Your sites and passwords stay on this Mac: sites are saved only in IDEPlus' settings, and passwords are kept by macOS in the Keychain (service "IDEPlus FTP"), never in IDEPlus' settings. Nothing is sent anywhere except to your own FTP server when you connect. Passwords are passed to curl through stdin so they don't show in the process list. Plain FTP and FTPS are supported; SFTP is not (yet).

## Languages, autocomplete and clips

Each language is a small JSON file in IDEPlus' own formats, shipped inside the app:

| Folder | Extension | What |
|---|---|---|
| `Resources/Syntax/` | `.ipsyntax` | One language: extensions, comments, quotes, keyword groups, patterns, colours |
| `Resources/Snippets/` | `.ipsnip` | Autocomplete templates for a language |
| `Resources/Clips/` | `.ipclip` | A clip library for the Clips tab |

The format is described at the top of [SyntaxFiles.swift](Sources/IDEPlus/SyntaxFiles.swift). To add or replace a language, see [docs/adding-a-language.md](docs/adding-a-language.md). Edit a file and rebuild, or put your own files in a folder and choose it with Document > Syntax > Choose Syntax Folder…; a file there with the same `name` replaces the built-in one. Document > Syntax > Reload Syntax Files picks up changes without restarting, and the Syntax menu shows any file that failed to load.

- **Autocomplete:** type a trigger word such as `if` and press **Space**: it becomes the template, with the cursor where `{{cursor}}` is. `"lineStart": true` triggers only expand at the start of a line. Turn it off in Document > Auto-completion.
- **Clips:** the **Clips** tab in the left panel (View > Clip Library, Ctrl-Cmd-C) lists each library. Hover an entry to preview it, double-click to insert it at the cursor (replacing any selection).

## Features

- One window with document tabs (click the × or middle-click to close; Ctrl-Tab, Cmd-Shift-[ / ] and Cmd-1…9 switch tabs)
- Directory window: a folder tree on the left (View > Directory Window, Cmd-Shift-D)
- Line numbers, current-line highlight, word wrap (Ctrl-Shift-W), font and size (View menu)
- Modern look (View menu): VS Code Light+/Dark+ colors, indent guides, matching-bracket highlight, roomier lines. Turn it off for classic colors.
- Smart editing (Document menu): auto-close brackets, quotes and HTML tags, wrap a selection in brackets or quotes, smart indent after `{`, `:` (Python) and opening tags, backspace removes an empty pair
- PHP files are highlighted as HTML with the PHP, `<script>` and `<style>` parts in their own languages
- Syntax highlighting for C/C++/Obj-C, C#, CSS, Go, HTML/XML, Java/Kotlin, JavaScript/TypeScript, JSON, Markdown, PHP, Python, Ruby, Rust, Shell, SQL, Swift, INI and YAML
- Find/replace bar with regex, match case and whole word; `\n` and `\t` work in regex replacements (Cmd-F, Opt-Cmd-F, Cmd-G, Cmd-Shift-G, Cmd-E)
- Go to line (Cmd-L)
- Encodings: detects BOMs, UTF-8, and Windows Latin 1. Saves in UTF-8 (with or without BOM), UTF-16, Latin encodings, Shift JIS, EUC-KR, GB 18030, Big5 or Windows-1251. File > Reopen with Encoding re-reads a file in another encoding.
- Line endings: detects and keeps LF / CRLF / CR; change them from the status bar
- Line commands: duplicate (Cmd-D), delete (Cmd-Shift-K), move up/down (Ctrl-Cmd-↑/↓), join (Cmd-J)
- Format: toggle comment (Cmd-/), indent / unindent (Cmd-] / Cmd-[, or Tab / Shift-Tab on a selection), change case, sort, remove duplicate lines, trim trailing whitespace, tabs ↔ spaces
- Auto-indent, tab width, insert spaces for tabs, insert date/time (F5)
- Separate undo history per document, recent files, reopens the tabs you left open at launch (FTP files are downloaded again), warns when a file changes on disk
- View in Browser (Cmd-B), Reveal in Finder, Print

## Development

- `IDEPLUS_SYNTAX_REPORT=1 .build/debug/IDEPlus` lists the languages, autocomplete and clip libraries that loaded, and how sample code is coloured.
- `IDEPLUS_SELFTEST=1 .build/debug/IDEPlus` runs the built-in checks (editing commands, smart editing, find/replace, encoding and line-ending round-trips, .ipsyntax/.ipsnip/.ipclip formats, highlighting, FTP listing formats).
- Live FTP checks against the local test server:
  `python3 tools/ftp_test_server.py /tmp/ftproot 2121 tester test-pass-123` then
  `IDEPLUS_SELFTEST=1 IDEPLUS_FTP_TEST=127.0.0.1:2121:tester:test-pass-123 .build/debug/IDEPlus`
- `IDEPLUS_SNAPSHOT_DIR=/some/dir build/IDEPlus.app/Contents/MacOS/IDEPlus files…` saves a PNG of each tab and quits (add `IDEPLUS_SNAPSHOT_FIND=1` to show the find bar).

## Releasing a version

1. Set the version in `Resources/Info.plist` (`CFBundleShortVersionString`), for example `1.1.0`.
2. Add what changed to [CHANGELOG.md](CHANGELOG.md).
3. Commit, then tag the commit: `git tag v1.1.0` and push the tag with `git push origin v1.1.0`.

The build number is set by `build.sh` from the number of commits, so it never needs changing by hand.

## Not built yet

Still missing: SFTP, hex viewer, find in files, user tools (running compilers), code folding, column/block select mode toggle (Option-drag already works), and spell check.
