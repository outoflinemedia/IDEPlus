# Changelog

What changed in each version of IDEPlus. Newest first.

Version numbers are `major.minor.fix`: the first changes for big changes, the middle for new features, the last for fixes only. The build number (shown in IDEPlus > About IDEPlus) is set automatically by `build.sh`.

## Unreleased

- The FTP site menu starts on "Choose a site…" and picking a site connects, so the menu always shows the site the tree is on. Nothing connects at launch. Add or Edit Sites… is at the bottom of the menu; the Connect and ⚙ buttons are gone.

## 1.0.0 (2026-10-22)

The first release.

**Editing files on your FTP server**
- Open files straight from FTP or FTPS sites; every save uploads them back, with a clear ✓ or ⚠︎ and Try Again.
- FTP Sites window: add, edit and test sites. Your sites stay on this Mac, and passwords are kept by macOS in your Keychain, not by IDEPlus.
- The Keychain is asked once per site per launch.
- File > Show FTP Temporary Folder shows the local copies, in a folder per login (`user@host`).

**Favorites**
- Projects of FTP files below the FTP tree, from any of your sites.
- Add files from the FTP list without opening them, drag them in, or click the star on a tab. If no project is selected, a guided step asks where they should go.
- Open All, filter, rename, and drag files between projects. The site name shows under each file.
- With more than 10 projects, they all start closed at launch. Favorites never open by themselves.

**The editor**
- Tabs, line numbers, current-line highlight, word wrap, modern or classic look.
- Syntax colours for PHP, HTML, JavaScript, CSS, SQL, Python and more, with PHP, `<script>` and `<style>` parts coloured in their own language.
- Smart editing (auto-close brackets, quotes and tags; Tab steps past closers), autocomplete templates, and a Clips library.
- Find and replace with regular expressions, go to line, line and format commands, encodings and line endings.
- Reopens the tabs you left open, including FTP files.
- With no tabs open, a small game of Space Rocks.

**Safety**
- Saved sites and favorites from older versions are read safely. Anything that can't be read is kept aside, never overwritten, and you're told once.
