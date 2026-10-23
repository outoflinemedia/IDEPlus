# Favorites

Quick access to the FTP files you're working on, grouped by project, across FTP sites.

## Stage 1: Favorites panel (built)

Menu: **Favorites** (Add Current File to Project ⇧⌘A, New Project…, Open All in Current Project, Show Favorites Panel).

**Hiding the panel:** only from the menu, Favorites > Show Favorites Panel. The FTP tree takes the full height; stars, Add to Project and ⇧⌘A keep working. Favorites can't be turned off completely, by design.

Lives in the FTP tab, below the FTP folder tree, with a draggable divider between them.

```
┌ Local │ FTP │ Clips ───────────────┐
│ [My site ▾] [Connect] ⚙            │
│ ↑ /public_html                ⟳    │
│ ▸ css                              │
│ ▾ wp-content                       │  FTP tree; favorite files show a ★
│     ★ header.php                   │
│       footer.php                   │
│ ──────────── drag to resize ────── │
│ FAVORITES   [filter…]  [+📁] [★+]  │
│ ▾ 📁 Client A redesign   (selected)│
│     ★ header.php     mysite.com    │  each file shows its site
│     ★ style.css      mysite.com    │
│     ★ config.php     staging.com   │  one folder can mix sites
│ ▸ 📁 Blog fixes                    │
│   ★ .htaccess        mysite.com    │  items can sit outside folders
└────────────────────────────────────┘
```

- **Only FTP files** are favorites (not local files, not folders, not lines).
- **Folders = projects.** Your own named folders; a folder can hold files from any FTP site.
- **Add:** select a folder, click ★+ to add the current tab's file to it.
- **Add straight from the FTP tree, without opening the file:** right-click > Add to Project, or select several files (Cmd-click / Shift-click) and add them together, or drag them from the FTP tree onto a project folder.
- **Guided step when no project is selected.** Adding never fails or scolds; it asks where the file should go:

  ```
  ┌ Add “header.php” to a project ─────────────┐
  │  ○ Client A redesign                        │  existing projects, most recent first
  │  ○ Blog fixes                               │
  │  ● New project: [ mysite.com            ]   │  name suggested from the site
  │                                             │
  │  [x] Make this the current project          │
  │                        [Cancel]  [Add]      │
  └─────────────────────────────────────────────┘
  ```

  With no projects yet, it goes straight to "New project", with the name already filled in. After that, the chosen project stays selected, so the next adds go there without asking.
- **Empty panel shows the first step:** with no projects, the Favorites panel shows a short hint ("Keep the files you're working on together") and a **Create a project** button, instead of a blank list.
- **Always visible which project is current:** the selected project is highlighted and named in the panel header ("Adding to: Client A redesign"), so it's clear where ★+ and Add to Project will put things.
- **Star on each FTP tab:** filled if the file is a favorite; click to add (to the selected folder) or remove.
- **Remove:** right-click > Remove, or Delete key. Removes the shortcut only, never the file on the server.
- **Organise:** drag favorites in and out of folders and up and down; +📁 makes a folder; rename folders.
- **Open:** double-click. If it's on a site you're not connected to, IDEPlus connects first (Keychain password) and downloads it. Save still uploads.
- **Open All:** right-click a folder > Open All opens every file in that project.
- **Remember last project:** the current project stays selected between launches. Favorites never open by themselves: at launch IDEPlus reopens only the tabs you left open (FTP ones are downloaded again), however many favorites you have.
- **Stars in the FTP tree** mark favorite files while browsing a site.
- **Keeping it tidy from day one:** a filter box at the top of the panel, and folders stay collapsed unless opened (IDEPlus remembers which were open). With more than 10 projects, they all start closed at launch.
- **Storage:** IDEPlus' settings on this Mac only. Never uploaded, never holds passwords. Each favorite stores the site's id and the file path.

## Stage 2 (not built yet): Manage Favorites window

For when the panel gets crowded. Bookmarks > Manage…:

- search, multi-select to move or remove, rename, sort by name, site or date added
- **archive** finished projects: they leave the panel and live in this window; restore anytime
- **focus on one project:** a "show only this folder" toggle in the panel
- favorites whose file no longer exists on the server are greyed out for easy clean-up
