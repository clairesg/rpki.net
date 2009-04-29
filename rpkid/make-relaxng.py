"""
Script to generate rpki/relaxng.py.

$Id$

Copyright (C) 2007--2008  American Registry for Internet Numbers ("ARIN")

Permission to use, copy, modify, and distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND ARIN DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS.  IN NO EVENT SHALL ARIN BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
"""

schemas = ("left_right", "up_down", "publication")

format_1 = """\
# Automatically generated, do not edit.

import lxml.etree
"""

format_2 = """\
## @var %(name)s
## Parsed RelaxNG %(name)s schema
%(name)s = lxml.etree.RelaxNG(lxml.etree.fromstring('''%(rng)s'''))
"""

print format_1

for name in schemas:
  print format_2 % {
    "name" : name,
    "rng"  : open(name.replace("_", "-") + "-schema.rng").read() }
