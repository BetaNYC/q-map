QMap Icon Mono — README and manifest
====================================

File:     qmap-icon-mono-italic.woff2
Family:   QMap Icon Mono, Italic (PostScript name QMapIconMono-Italic)

This is a MODIFIED version of New Computer Modern Mono 10, Book Italic,
version 7.1.0, (C) 2019-2021 Antonis Tsolomitis, released under the GUST Font
License (below). Original file: NewCMMono10-BookItalic.otf, as carried in the
d26-gi-web-map project. The original is distributed on CTAN:
https://ctan.org/pkg/newcomputermodern

Changes from the original:
  - subset to the lowercase letters a-z, U+0061-007A (26 characters), the
    only characters a category mark can be;
  - OpenType layout features removed;
  - the FFTM and PfEd tables dropped;
  - converted to WOFF2;
  - renamed (file name, family, full and PostScript names), as clause 1 of
    the GUST Font License requests of derived works.

Used by the Queens Resource Map web app for the one- and two-letter category
marks (web/src/fonts.css, --font-mono-icon in web/src/tokens.css).

Regenerate from the original:

  uvx --from 'fonttools[woff]' pyftsubset NewCMMono10-BookItalic.otf \
    --unicodes="U+0061-007A" --layout-features='' --flavor=woff2 \
    --output-file=subset.woff2
  then rename name IDs 1, 2, 3, 4, 6, 16, 17 and the CFF FontName/FamilyName/
  FullName to QMap Icon Mono (see METHODOLOGY.md, 2026-10-21).

The GUST Font License, version 1.0, as published at
http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt:

% This is version 1.0, dated 22 June 2009, of the GUST Font License.
% (GUST is the Polish TeX Users Group, http://www.gust.org.pl)
%
% For the most recent version of this license see
% http://www.gust.org.pl/fonts/licenses/GUST-FONT-LICENSE.txt
% or
% http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt
%
% This work may be distributed and/or modified under the conditions
% of the LaTeX Project Public License, either version 1.3c of this
% license or (at your option) any later version.
%
% Please also observe the following clause:
% 1) it is requested, but not legally required, that derived works be
%    distributed only after changing the names of the fonts comprising this
%    work and given in an accompanying "manifest", and that the
%    files comprising the Work, as listed in the manifest, also be given
%    new names. Any exceptions to this request are also given in the
%    manifest.
%
%    We recommend the manifest be given in a separate file named
%    MANIFEST-<fontid>.txt, where <fontid> is some unique identification
%    of the font family. If a separate "readme" file accompanies the Work,
%    we recommend a name of the form README-<fontid>.txt.
%
% The latest version of the LaTeX Project Public License is in
% http://www.latex-project.org/lppl.txt and version 1.3c or later
% is part of all distributions of LaTeX version 2006/05/20 or later.
