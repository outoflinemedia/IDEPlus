# Adding or replacing a language

Every language IDEPlus colours is one `.ipsyntax` file in [Resources/Syntax](../Resources/Syntax). The full list of fields is at the top of [SyntaxFiles.swift](../Sources/IDEPlus/SyntaxFiles.swift).

## Status

| Language | File | Keyword lists |
|---|---|---|
| PHP | `php.ipsyntax` | Own, from the PHP manual |
| JavaScript | `javascript.ipsyntax` | Own, from the ECMAScript spec and common browser APIs |
| CSS | `css.ipsyntax` | Own, from the CSS specs |
| SQL | `sql.ipsyntax` | Own, SQL standard plus MySQL |
| Python | `python.ipsyntax` | Own, generated from Python itself |
| HTML / XML, Markdown, JSON, YAML, INI, Shell, Swift, Go, Rust, TypeScript, Kotlin, SCSS | various | Own (patterns, written for IDEPlus) |
| C / C++, C#, Java, JSP, Perl, Ruby, VBScript | not in the repository | Kept only on the original Mac (ignored by git) until redone with own lists; their autocomplete templates are already in the repo and start working once a language file is added |

All autocomplete templates (`Resources/Snippets`) and clip libraries (`Resources/Clips`) are IDEPlus' own: templates written for IDEPlus, and clips for HTML elements, CSS, HTML entities, characters and control characters, generated from the HTML and CSS lists and Python's Unicode tables.

## Steps

1. Copy [language-template.ipsyntax](language-template.ipsyntax) to `Resources/Syntax/<language>.ipsyntax` (or overwrite the existing file to replace a language).
2. Set `name` (shown in menus; must be unique), `extensions`, and the comment and quote markers.
3. Fill the `keywordGroups` from the language's official reference: its specification or manual. Groups are coloured with `keyword`, `type`, `attribute`, `preprocessor`, `tag` or `heading`.
4. Run `./build.sh`, then open a file of that type. Or, without rebuilding: put the file in a folder, choose it with Document > Syntax > Choose Syntax Folder…, and use Reload Syntax Files.
5. If something doesn't load, the Syntax menu shows the problem, and `IDEPLUS_SYNTAX_REPORT=1 .build/debug/IDEPlus` lists every language with any errors.

Keep lists lean: the language's own keywords and its core built-ins. Thousands of library class names slow highlighting and add little.

Autocomplete (`.ipsnip`, in `Resources/Snippets`) and clip libraries (`.ipclip`, in `Resources/Clips`) work the same way; see the examples there.
