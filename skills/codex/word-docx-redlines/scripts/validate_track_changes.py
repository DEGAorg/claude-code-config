#!/usr/bin/env python3
"""
Validate Track Changes in .docx files.

Extract and audit existing w:ins/w:del elements from Word documents
by inspecting the raw XML. Use for verifying that a redlined document
correctly implements a change specification.

Usage (as a library):
    from validate_track_changes import DocxTrackChangeReader

    reader = DocxTrackChangeReader("output.docx")
    reader.summary()
    changes = reader.changes_near("Section A - Acceptance")
    reader.print_changes(changes)

Usage (CLI):
    python validate_track_changes.py output.docx
    python validate_track_changes.py output.docx --section "Section A - Acceptance"
    python validate_track_changes.py output.docx --check-pattern "Section A - Acceptance" ".."
    python validate_track_changes.py output.docx --compare baseline.docx
"""

import re
import sys
import html as html_mod
import subprocess
import argparse
from dataclasses import dataclass, field


@dataclass
class TrackedChange:
    change_type: str  # "insertion" or "deletion"
    text: str
    offset: int
    author: str = ""
    date: str = ""


@dataclass
class SectionChanges:
    section_pattern: str
    offset: int
    insertions: list = field(default_factory=list)
    deletions: list = field(default_factory=list)


class DocxTrackChangeReader:
    """Read and audit Track Changes from a .docx file via raw XML."""

    def __init__(self, docx_path):
        self.path = docx_path
        self.xml = self._extract_xml()

    def _extract_xml(self):
        result = subprocess.run(
            ["unzip", "-p", self.path, "word/document.xml"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Failed to extract XML from {self.path}: {result.stderr}")
        return result.stdout

    @staticmethod
    def _extract_wt_text(xml_fragment):
        """Extract text from w:t tags."""
        texts = re.findall(r'<w:t[^>]*>(.*?)</w:t>', xml_fragment, re.DOTALL)
        return ''.join(html_mod.unescape(t) for t in texts)

    @staticmethod
    def _extract_del_text(xml_fragment):
        """Extract text from w:delText tags."""
        texts = re.findall(r'<w:delText[^>]*>(.*?)</w:delText>', xml_fragment, re.DOTALL)
        return ''.join(html_mod.unescape(t) for t in texts)

    @staticmethod
    def _extract_author(tag_xml):
        m = re.search(r'w:author="([^"]*)"', tag_xml)
        return m.group(1) if m else ""

    @staticmethod
    def _extract_date(tag_xml):
        m = re.search(r'w:date="([^"]*)"', tag_xml)
        return m.group(1) if m else ""

    def count(self):
        """Count total insertions and deletions."""
        ins = len(re.findall(r'<w:ins ', self.xml))
        dels = len(re.findall(r'<w:del ', self.xml))
        return {"insertions": ins, "deletions": dels}

    def summary(self):
        """Print a summary of track changes."""
        c = self.count()
        print(f"Document: {self.path}")
        print(f"  Insertions (w:ins): {c['insertions']}")
        print(f"  Deletions  (w:del): {c['deletions']}")
        print(f"  XML size: {len(self.xml):,} chars")

    def all_changes(self):
        """Extract all tracked changes from the document."""
        changes = []
        for m in re.finditer(r'<w:ins\b([^>]*)>(.*?)</w:ins>', self.xml, re.DOTALL):
            text = self._extract_wt_text(m.group(2))
            if text.strip():
                changes.append(TrackedChange(
                    change_type="insertion", text=text,
                    offset=m.start(),
                    author=self._extract_author(m.group(1)),
                    date=self._extract_date(m.group(1)),
                ))
        for m in re.finditer(r'<w:del\b([^>]*)>(.*?)</w:del>', self.xml, re.DOTALL):
            text = self._extract_del_text(m.group(2))
            if text.strip():
                changes.append(TrackedChange(
                    change_type="deletion", text=text,
                    offset=m.start(),
                    author=self._extract_author(m.group(1)),
                    date=self._extract_date(m.group(1)),
                ))
        changes.sort(key=lambda c: c.offset)
        return changes

    def changes_near(self, section_pattern, context_after=8000, context_before=500):
        """Find tracked changes near a section heading pattern."""
        matches = list(re.finditer(section_pattern, self.xml))
        if not matches:
            return []

        results = []
        for m in matches:
            start = max(0, m.start() - context_before)
            end = min(len(self.xml), m.end() + context_after)
            chunk = self.xml[start:end]

            ins_texts = []
            for ins_m in re.finditer(r'<w:ins\b[^>]*>(.*?)</w:ins>', chunk, re.DOTALL):
                text = self._extract_wt_text(ins_m.group(1))
                if text.strip():
                    ins_texts.append(text)

            del_texts = []
            for del_m in re.finditer(r'<w:del\b[^>]*>(.*?)</w:del>', chunk, re.DOTALL):
                text = self._extract_del_text(del_m.group(1))
                if text.strip():
                    del_texts.append(text)

            results.append(SectionChanges(
                section_pattern=section_pattern,
                offset=m.start(),
                insertions=ins_texts,
                deletions=del_texts,
            ))
        return results

    def is_tracked_insertion(self, search_text):
        """Check if search_text appears inside a w:ins element."""
        m = re.search(re.escape(search_text[:80]), self.xml)
        if not m:
            return False
        lookback = self.xml[max(0, m.start() - 3000):m.end()]
        ins_opens = list(re.finditer(r'<w:ins\b[^>]*>', lookback))
        ins_closes = list(re.finditer(r'</w:ins>', lookback))
        if ins_opens:
            last_open = ins_opens[-1]
            last_close = ins_closes[-1] if ins_closes else None
            if last_close is None or last_open.start() > last_close.start():
                return True
        return False

    def check_pattern_fix(self, section_pattern, bad_pattern, context_after=8000):
        """Verify that bad_pattern was deleted and not re-introduced near a section."""
        sections = self.changes_near(section_pattern, context_after)
        if not sections:
            return {"found": False, "section_exists": False}

        for sec in sections:
            for dt in sec.deletions:
                if bad_pattern in dt:
                    still_present = any(bad_pattern in it for it in sec.insertions)
                    return {
                        "found": True,
                        "section_exists": True,
                        "deleted": True,
                        "still_in_insertion": still_present,
                        "pass": not still_present,
                    }
        return {"found": False, "section_exists": True}

    def find_text(self, search_text):
        """Find all occurrences of search_text in the XML, returning context."""
        results = []
        for m in re.finditer(re.escape(search_text), self.xml):
            chunk = self.xml[max(0, m.start() - 1000):min(len(self.xml), m.end() + 500)]
            lookback = self.xml[max(0, m.start() - 3000):m.start()]
            ins_open = lookback.rfind("<w:ins")
            ins_close = lookback.rfind("</w:ins>")
            del_open = lookback.rfind("<w:del")
            del_close = lookback.rfind("</w:del>")
            results.append({
                "offset": m.start(),
                "in_insertion": ins_open > ins_close,
                "in_deletion": del_open > del_close,
                "context": chunk,
            })
        return results

    @staticmethod
    def print_changes(section_changes_list, max_text=300):
        """Pretty-print extracted section changes."""
        for sec in section_changes_list:
            print(f"\n  Section '{sec.section_pattern}' at offset {sec.offset}:")
            print(f"  Insertions ({len(sec.insertions)}):")
            for i, text in enumerate(sec.insertions):
                display = text[:max_text] + ("..." if len(text) > max_text else "")
                print(f"    INS[{i}]: \"{display}\"")
            print(f"  Deletions ({len(sec.deletions)}):")
            for i, text in enumerate(sec.deletions):
                display = text[:max_text] + ("..." if len(text) > max_text else "")
                print(f"    DEL[{i}]: \"{display}\"")


def compare_documents(baseline_path, output_path):
    """Compare track change counts between baseline and output."""
    baseline = DocxTrackChangeReader(baseline_path)
    output = DocxTrackChangeReader(output_path)

    bc = baseline.count()
    oc = output.count()

    print(f"Baseline ({baseline_path}):")
    print(f"  Insertions: {bc['insertions']}, Deletions: {bc['deletions']}")
    print(f"Output ({output_path}):")
    print(f"  Insertions: {oc['insertions']}, Deletions: {oc['deletions']}")
    print(f"Delta:")
    print(f"  Insertions: {oc['insertions'] - bc['insertions']:+d}")
    print(f"  Deletions:  {oc['deletions'] - bc['deletions']:+d}")


def main():
    parser = argparse.ArgumentParser(description="Validate Track Changes in .docx files")
    parser.add_argument("docx", help="Path to the .docx file to inspect")
    parser.add_argument("--section", help="Section heading pattern to search near")
    parser.add_argument("--context", type=int, default=8000, help="XML chars after heading (default: 8000)")
    parser.add_argument("--check-pattern", nargs=2, metavar=("SECTION", "PATTERN"),
                        help="Check if PATTERN was fixed (deleted, not re-inserted) near SECTION")
    parser.add_argument("--compare", metavar="BASELINE", help="Compare against a baseline .docx")
    parser.add_argument("--all", action="store_true", help="Print all tracked changes")
    args = parser.parse_args()

    reader = DocxTrackChangeReader(args.docx)
    reader.summary()

    if args.compare:
        print()
        compare_documents(args.compare, args.docx)

    if args.section:
        changes = reader.changes_near(args.section, context_after=args.context)
        if changes:
            reader.print_changes(changes)
        else:
            print(f"\n  Section '{args.section}' not found in document.")

    if args.check_pattern:
        section, pattern = args.check_pattern
        result = reader.check_pattern_fix(section, pattern, context_after=args.context)
        print(f"\n  Pattern check: '{pattern}' near '{section}'")
        if result.get("pass"):
            print(f"  PASS: Pattern found in deletion and not in insertion.")
        elif result.get("found"):
            print(f"  FAIL: Pattern found in deletion but STILL present in insertion.")
        elif result.get("section_exists"):
            print(f"  NOT FOUND: Pattern not found in any deletion near this section.")
        else:
            print(f"  NOT FOUND: Section heading not found in document.")

    if args.all:
        changes = reader.all_changes()
        print(f"\nAll tracked changes ({len(changes)} total):")
        for c in changes:
            tag = "INS" if c.change_type == "insertion" else "DEL"
            display = c.text[:200] + ("..." if len(c.text) > 200 else "")
            print(f"  [{tag}] @{c.offset} by {c.author}: \"{display}\"")

    if not any([args.section, args.check_pattern, args.compare, args.all]):
        print("\nUse --section, --check-pattern, --compare, or --all for detailed output.")


if __name__ == "__main__":
    main()
