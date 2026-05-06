---
name: word-docx-redlines
description: >-
  Create, read, validate, and compare Word (.docx) documents with Track Changes.
  Write real Track Changes XML (w:ins/w:del) into .docx files for native
  accept/reject in Word. Validate that a redlined .docx correctly implements
  a change specification by extracting and auditing existing tracked changes.
  Generate redline comparison documents from two versions. Use when the user
  asks to work with Word documents, .docx files, tracked changes, redlines,
  document comparison, validating redlines, auditing changes, or modifying
  Word files programmatically.
---

# Word Document Redlines & Track Changes

## Prerequisites

```bash
brew install pandoc
pip install python-docx   # or: python3 -m venv .venv && source .venv/bin/activate && pip install python-docx
```

## Core Capabilities

### 1. Extract text from .docx

Use pandoc for clean text extraction (better than python-docx `.text` which misses field codes):

```bash
pandoc document.docx -t plain --wrap=none
```

python-docx `.text` misses content in Word field codes, bookmarks, and complex formatting. To get ALL text from a paragraph:

```python
def full_text(para):
    return "".join(t.text or "" for t in para._element.findall(".//" + qn("w:t")))
```

### 2. Iterate paragraphs in document order

Body paragraphs and table cell paragraphs are separate in python-docx:

```python
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph

body = doc.element.body
for child in body:
    if child.tag == qn("w:p"):
        para = Paragraph(child, body)
    elif child.tag == qn("w:tbl"):
        # table - iterate rows/cells separately
        pass
```

### 3. Write real Track Changes XML

Use `w:del` for deletions and `w:ins` for insertions. These produce native accept/reject buttons in Word.

See `scripts/track_changes_helpers.py` for ready-to-use helper functions: `make_del()`, `make_ins()`, `replace_para()`, `delete_para()`, `insert_para_after()`.

### 4. Generate a redline comparison document

**Recommended workflow:**

1. Extract text from original .docx via pandoc
2. Normalize both versions (strip markdown, fix unicode, collapse whitespace)
3. Diff with `difflib.SequenceMatcher` (line-level alignment, word-level diff for changes)
4. Apply changes as Track Changes XML into a copy of the original .docx

For step 4, use **targeted search** (find paragraphs by unique text snippet) rather than index-based or fuzzy alignment. See the "Targeted Approach" section below.

## Key Lessons / Gotchas

### Text normalization is critical

The same text looks different depending on how you extract it. Always normalize before comparing:

```python
def norm(text):
    text = text.replace("\xa0", " ")          # non-breaking spaces (VERY common in .docx)
    text = text.replace("\u2013", "-")         # en-dash
    text = text.replace("\u2014", " - ")       # em-dash
    text = text.replace("\u201c", '"')         # smart quotes
    text = text.replace("\u201d", '"')
    text = text.replace("\u2018", "'")
    text = text.replace("\u2019", "'")
    text = re.sub(r"[ \t]+", " ", text)        # collapse whitespace
    return text.strip()
```

### pandoc text != python-docx text

- pandoc renders Word field codes (e.g., `[INSERT DATE]`); python-docx shows raw XML (e.g., `]`)
- pandoc joins table cells into one line per row; python-docx gives each cell as a separate paragraph
- pandoc includes table separator lines (`---`); filter these out

### Paragraph matching strategy

**DO NOT** rely on fuzzy alignment between pandoc-extracted text and python-docx paragraphs. Instead:

1. **Targeted search**: Find paragraphs by unique text snippets using `full_text()`:
   ```python
   def find_para(paras, snippet, start=0):
       for i in range(start, len(paras)):
           if snippet in full_text(paras[i]):
               return i
       return None
   ```

2. **Section-heading anchored**: Find the section heading first, then search nearby paragraphs.

3. **Refresh after inserts**: Call `get_body_paras(doc)` again after inserting/deleting paragraphs.

### Track Changes XML structure

Deleted text uses `w:delText` (not `w:t`):
```xml
<w:del w:id="1" w:author="Author" w:date="2026-01-01T00:00:00Z">
  <w:r><w:delText xml:space="preserve">old text</w:delText></w:r>
</w:del>
```

Inserted text uses `w:ins` wrapping a normal run:
```xml
<w:ins w:id="2" w:author="Author" w:date="2026-01-01T00:00:00Z">
  <w:r><w:t xml:space="preserve">new text</w:t></w:r>
</w:ins>
```

### Preserving formatting

When rewriting a paragraph's content, capture the reference `rPr` (run properties) from the first run BEFORE clearing, then apply it to new runs. This preserves font, size, bold, etc.

## Targeted Approach (recommended for known changes)

When you know exactly what changed (e.g., from a change log), the most reliable method is:

1. Copy the original .docx
2. For each change, search for a unique text snippet to find the paragraph
3. Apply the specific Track Change (delete, insert, or word-level diff)

This avoids all fuzzy matching problems and produces clean, accurate results.

## Validating Track Changes (auditing an existing redline)

When the user asks you to **validate**, **verify**, or **audit** a .docx that already contains Track Changes against a change specification, ground truth document, or list of expected changes, use the raw XML inspection approach below. python-docx does NOT expose existing `w:ins`/`w:del` elements through its API — you must work with the XML directly.

### Raw XML extraction

A .docx is a ZIP archive. Extract `word/document.xml` without writing to disk:

```bash
unzip -p "Document.docx" word/document.xml | python3 -c "
import sys
xml = sys.stdin.read()
print(f'Size: {len(xml)} chars')
"
```

### Counting track changes

```bash
unzip -p "Document.docx" word/document.xml | python3 -c "
import sys, re
xml = sys.stdin.read()
print(f'Insertions (w:ins): {len(re.findall(r\"<w:ins \", xml))}')
print(f'Deletions (w:del): {len(re.findall(r\"<w:del \", xml))}')
"
```

### Section-anchored extraction

The core validation technique: find a section heading in the raw XML, grab a character window around it, then extract all `w:ins` and `w:del` elements within that window.

```python
import re, html as html_mod

def extract_text_from_xml(xml_fragment):
    """Extract text from w:t tags in an XML fragment."""
    texts = re.findall(r'<w:t[^>]*>(.*?)</w:t>', xml_fragment, re.DOTALL)
    return ''.join(html_mod.unescape(t) for t in texts)

def extract_del_text(xml_fragment):
    """Extract text from w:delText tags in an XML fragment."""
    texts = re.findall(r'<w:delText[^>]*>(.*?)</w:delText>', xml_fragment, re.DOTALL)
    return ''.join(html_mod.unescape(t) for t in texts)

def extract_tracked_changes_near(xml, section_pattern, context_after=8000):
    """Find a section heading and extract all tracked changes nearby."""
    matches = list(re.finditer(section_pattern, xml))
    if not matches:
        return None

    results = []
    for m in matches:
        start = max(0, m.start() - 500)
        end = min(len(xml), m.end() + context_after)
        chunk = xml[start:end]

        insertions = re.findall(r'<w:ins\b[^>]*>(.*?)</w:ins>', chunk, re.DOTALL)
        deletions = re.findall(r'<w:del\b[^>]*>(.*?)</w:del>', chunk, re.DOTALL)

        ins_texts = [extract_text_from_xml(i) for i in insertions]
        del_texts = [extract_del_text(d) for d in deletions]

        results.append({
            'offset': m.start(),
            'insertions': [t for t in ins_texts if t.strip()],
            'deletions': [t for t in del_texts if t.strip()],
        })
    return results
```

### Checking if specific text is tracked as an insertion

Search for the text in the XML, then walk backwards to see if it's enclosed in a `w:ins` tag:

```python
def is_text_tracked_as_insertion(xml, search_text):
    """Check whether search_text appears inside a w:ins element."""
    m = re.search(re.escape(search_text), xml)
    if not m:
        return False
    chunk = xml[max(0, m.start() - 3000):m.end()]
    ins_opens = list(re.finditer(r'<w:ins\b[^>]*>', chunk))
    ins_closes = list(re.finditer(r'</w:ins>', chunk))
    if ins_opens:
        last_open = ins_opens[-1]
        last_close = ins_closes[-1] if ins_closes else None
        if last_close is None or last_open.start() > last_close.start():
            return True
    return False
```

### Detecting specific text patterns (quote fixes, double periods, typos)

When validating typographical fixes, compare the deleted text against the inserted text for the specific pattern:

```python
def check_pattern_fix(xml, section_pattern, bad_pattern, context_after=8000):
    """Check if bad_pattern appears in a deletion near section_pattern,
    and confirm the corresponding insertion does not contain it."""
    results = extract_tracked_changes_near(xml, section_pattern, context_after)
    if not results:
        return {'found': False}

    for r in results:
        for dt in r['deletions']:
            if bad_pattern in dt:
                in_any_insertion = any(bad_pattern in it for it in r['insertions'])
                return {
                    'found': True,
                    'deleted': True,
                    'still_in_insertion': in_any_insertion,
                    'pass': not in_any_insertion,
                }
    return {'found': False}
```

**Common patterns to check:**
- Double periods: `'..'` in deleted text, `'.'` (single) in insertion
- Missing quotes: `the Defined Term")` (no opening quote) → `the "Defined Term")`
- Single → double quotes: `('Example Term')` → `("Example Term")`
- Ellipsis: `'Section 1.1…,'` → `'Section 1.1,'`
- Typos: `'Section 2.1shall'` → `'Section 2.1 shall'`

### Validation methodology

When validating a redlined .docx against a change specification:

1. **Extract XML** from both the baseline .docx and the output .docx using `unzip -p`.
2. **Count track changes** in both to understand the baseline (the original may already contain changes from a prior redline round).
3. **For each change in the spec**, use section-anchored extraction to find the relevant tracked changes:
   - Identify the section heading pattern (e.g., `'Section A - Acceptance'`).
   - Extract all `w:ins` and `w:del` elements near that heading.
   - Compare deleted text against what the spec says should have been removed.
   - Compare inserted text against what the spec (or ground truth document) says should be present.
4. **For each change, report a verdict:**
   - **PASS**: The tracked change is present and correct (deletion matches what should be removed, insertion matches what should be added).
   - **FAIL**: The change is missing, incomplete, or incorrect (explain what's wrong).
   - **SKIP**: The change was already correct in the baseline document (no modification needed).
5. **Produce a summary table** with pass/fail/skip counts.

### Comparing baseline vs. output

When the baseline document already contains track changes from a prior round, you need to distinguish between inherited changes and new changes. Compare both documents:

```bash
# Count changes in baseline
unzip -p "baseline.docx" word/document.xml | python3 -c "
import sys, re; xml = sys.stdin.read()
print(f'Baseline - ins: {len(re.findall(r\"<w:ins \", xml))}, del: {len(re.findall(r\"<w:del \", xml))}')
"

# Count changes in output
unzip -p "output.docx" word/document.xml | python3 -c "
import sys, re; xml = sys.stdin.read()
print(f'Output - ins: {len(re.findall(r\"<w:ins \", xml))}, del: {len(re.findall(r\"<w:del \", xml))}')
"
```

If both have similar counts, verify that specific changes from the spec are present in the output but not in the baseline. Use the `w:author` attribute on track change elements to distinguish authors when multiple redline rounds exist.

### Adjusting context window size

The `context_after` parameter controls how much XML to scan after the section heading. Defaults to 8000 characters, which covers most sections. For long sections (e.g., a section with multiple bullet points), increase to 12000–18000. For short sections (e.g., a single-line fix), 3000–5000 is sufficient.

## Utility Scripts

- **`scripts/track_changes_helpers.py`**: Core helper functions for writing Track Changes XML into .docx files. Use as a library or read for reference.
- **`scripts/validate_track_changes.py`**: Functions for extracting and auditing existing Track Changes from .docx files via raw XML inspection. Use for validation workflows.
