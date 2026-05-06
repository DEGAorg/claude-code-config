#!/usr/bin/env python3
"""
Track Changes helpers for python-docx.
Provides functions to write real Word Track Changes (w:ins / w:del) into .docx files.

Usage:
    from track_changes_helpers import (
        full_text, find_para, get_body_paras, get_ref_rPr,
        clear_para_content, make_run, make_del, make_ins,
        replace_para, delete_para, insert_para_after, word_diff,
        apply_word_diff_to_para
    )
"""

import re
import copy
import difflib
from lxml import etree
from docx import Document
from docx.text.paragraph import Paragraph
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

_rid = [0]
AUTHOR = "Author"
DATE = "2026-01-01T00:00:00Z"


def set_author(author, date=None):
    global AUTHOR, DATE
    AUTHOR = author
    if date:
        DATE = date


def _nid():
    _rid[0] += 1
    return str(_rid[0])


def full_text(para):
    """Get ALL text from a paragraph, including field codes and complex runs."""
    return "".join(t.text or "" for t in para._element.findall(".//" + qn("w:t")))


def norm(text):
    """Normalize text for comparison."""
    text = text.replace("\xa0", " ")
    text = text.replace("\u2011", "-").replace("\u2013", "-").replace("\u2014", " - ")
    text = text.replace("\u201c", '"').replace("\u201d", '"')
    text = text.replace("\u2018", "'").replace("\u2019", "'")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def get_body_paras(doc):
    """Get all body-level paragraphs (excludes table cells)."""
    body = doc.element.body
    return [Paragraph(c, body) for c in body if c.tag == qn("w:p")]


def find_para(paras, snippet, start=0):
    """Find first paragraph containing snippet (using full_text)."""
    for i in range(start, len(paras)):
        if snippet in full_text(paras[i]):
            return i
    return None


def get_ref_rPr(para):
    """Extract formatting properties from first run, stripping color/strike/highlight."""
    for r_elem in para._element.findall(qn("w:r")):
        rPr = r_elem.find(qn("w:rPr"))
        if rPr is not None:
            rPr_copy = copy.deepcopy(rPr)
            for tag in (qn("w:color"), qn("w:strike"), qn("w:highlight"), qn("w:rStyle")):
                for el in rPr_copy.findall(tag):
                    rPr_copy.remove(el)
            return rPr_copy
    return None


def clear_para_content(para):
    """Remove all runs/tracked changes from paragraph, keeping pPr."""
    for child in list(para._element):
        if child.tag != qn("w:pPr"):
            para._element.remove(child)


def make_run(text, rPr=None):
    """Create a w:r element."""
    r = OxmlElement("w:r")
    if rPr is not None:
        r.append(copy.deepcopy(rPr))
    t = OxmlElement("w:t")
    t.set(qn("xml:space"), "preserve")
    t.text = text
    r.append(t)
    return r


def make_del(text, rPr=None):
    """Create a w:del element (tracked deletion)."""
    d = OxmlElement("w:del")
    d.set(qn("w:id"), _nid())
    d.set(qn("w:author"), AUTHOR)
    d.set(qn("w:date"), DATE)
    r = OxmlElement("w:r")
    if rPr is not None:
        r.append(copy.deepcopy(rPr))
    dt = OxmlElement("w:delText")
    dt.set(qn("xml:space"), "preserve")
    dt.text = text
    r.append(dt)
    d.append(r)
    return d


def make_ins(text, rPr=None):
    """Create a w:ins element (tracked insertion)."""
    ins = OxmlElement("w:ins")
    ins.set(qn("w:id"), _nid())
    ins.set(qn("w:author"), AUTHOR)
    ins.set(qn("w:date"), DATE)
    ins.append(make_run(text, rPr))
    return ins


def replace_para(para, new_text):
    """Delete old content, insert new content (both tracked)."""
    old_text = full_text(para)
    rPr = get_ref_rPr(para)
    clear_para_content(para)
    if old_text.strip():
        para._element.append(make_del(old_text, rPr))
    para._element.append(make_ins(new_text, rPr))


def delete_para(para):
    """Mark entire paragraph content as deleted."""
    text = full_text(para)
    if not text.strip():
        return
    rPr = get_ref_rPr(para)
    clear_para_content(para)
    para._element.append(make_del(text, rPr))


def insert_para_after(para, text):
    """Insert a new tracked-insertion paragraph after the given one."""
    rPr = get_ref_rPr(para)
    p = OxmlElement("w:p")
    if para._element.pPr is not None:
        p.append(copy.deepcopy(para._element.pPr))
    p.append(make_ins(text, rPr))
    para._element.addnext(p)
    return Paragraph(p, para._element.getparent())


def word_diff(old_text, new_text):
    """Compute word-level diff. Returns list of (op, text) tuples."""
    old_w = old_text.split()
    new_w = new_text.split()
    sm = difflib.SequenceMatcher(None, old_w, new_w, autojunk=False)
    ops = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            ops.append(("equal", " ".join(old_w[i1:i2])))
        elif tag == "delete":
            ops.append(("delete", " ".join(old_w[i1:i2])))
        elif tag == "insert":
            ops.append(("insert", " ".join(new_w[j1:j2])))
        elif tag == "replace":
            ops.append(("delete", " ".join(old_w[i1:i2])))
            ops.append(("insert", " ".join(new_w[j1:j2])))
    return ops


def apply_word_diff_to_para(para, old_text, new_text):
    """Rewrite paragraph with word-level Track Changes markup."""
    rPr = get_ref_rPr(para)
    clear_para_content(para)
    ops = word_diff(old_text, new_text)
    for i, (op, text) in enumerate(ops):
        prefix = " " if i > 0 else ""
        content = prefix + text
        if op == "equal":
            para._element.append(make_run(content, rPr))
        elif op == "delete":
            para._element.append(make_del(content, rPr))
        elif op == "insert":
            para._element.append(make_ins(content, rPr))
