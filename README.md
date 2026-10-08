# nim-docfmt

A Markdown formatter and linter for Nim comments and docstrings.

`nim-docfmt` formats and reflows the Markdown prose inside your comments and docstrings while guaranteeing that **all Nim code, tokens, spacing, and formatting outside comments remain 100% bit-for-bit identical**.

---

## Features

- **Zero-Mutation Guarantee**: Code outside comments is never altered. Indentation, blank lines, operators, expressions, and string literals are strictly preserved byte-for-byte.
- **Supports All Nim Comment Types**:
  - Regular single-line comments (`# ...`)
  - Docstring single-line comments (`## ...`)
  - Multi-line block comments (`#[ <arbitrary newlines and text> ]#`) including nested block comments
  - Multi-line docstring block comments (`##[ ... ]##`)
- **Markdown-Aware Reflow**:
  - Reflows prose paragraphs to configurable column widths (default: 80).
  - Preserves fenced code blocks (` ``` ` and `~~~`) completely verbatim without line wrapping.
  - Formats unordered (`-`, `*`, `+`) and ordered (`1.`) lists with clean hanging indentation.
  - Preserves Markdown headers (`#`, `##`, `###`), tables (`|...|`), blockquotes (`>`), and decorative banner delimiters.
  - Strips trailing whitespace on comment lines.
- **CI-Ready**: Built-in `--check` mode exits with code `1` if unformatted comments are detected, making it seamless to integrate into automated pipelines.

---

## Installation

```bash
nimble install https://github.com/elijahr/nim-docfmt
```

Or build locally:

```bash
git clone https://github.com/elijahr/nim-docfmt.git
cd nim-docfmt
nimble build -d:release
```

---

## Usage

### Check files for formatting (CI Mode)

```bash
nim-docfmt --check src/ tests/
```

Returns exit code `0` if all comments are formatted, or exit code `1` if any file contains comments needing reflow.

### Format files in-place

```bash
nim-docfmt --write src/ tests/
```

### Inspect diffs

```bash
nim-docfmt --diff src/my_module.nim
```

### Options

| Flag | Description | Default |
| :--- | :--- | :--- |
| `-c, --check` | Check if files are formatted (exit `1` on mismatch) | `false` |
| `-w, --write` | Write formatted changes in-place to files | `false` |
| `-d, --diff` | Display diffs of files needing formatting | `false` |
| `--max-width:N` | Target column wrap width for comment paragraphs | `80` |
| `--comments:on\|off` | Format regular comments (`#` and `#[ ]#`) | `on` |
| `--doc:on\|off` | Format doc comments (`##` and `##[ ]##`) | `on` |
| `-v, --version` | Show version and exit | |
| `-h, --help` | Show help and exit | |

---

## License

MIT License. See [LICENSE](LICENSE) for details.
