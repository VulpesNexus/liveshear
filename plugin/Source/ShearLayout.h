// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vixen420
//
// Shear for Illustrator is free software: you may redistribute it and/or
// modify it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version. It comes with ABSOLUTELY NO WARRANTY. See the
// file LICENSE, or <https://www.gnu.org/licenses/>, for the full text.
//
// Additional permission under GPL-3.0 section 7: this file may be combined with
// the Adobe Illustrator SDK, whose sample framework sources are compiled into
// every plugin built from it. See LICENSE-EXCEPTION.

//  ShearLayout.h -- where every control in the dialog sits.
//
//  Split out from ShearDialog.cpp so the arithmetic can be checked without
//  Windows, for the same reason ShearCurve.h was: the interesting question
//  about this table is whether it still describes a usable dialog at a display
//  scale nobody here has a monitor for.
//
//  The coordinates are in the units Windows calls 96 dots per inch, which is
//  the 100% scale, and every one of them is multiplied through the same
//  function. That is what makes the layout worth testing as data: if any
//  control could leave the window or land on top of another at 150%, it would
//  have to do so through rounding, because the shape is otherwise similar at
//  every scale.

#ifndef SHEAR_LAYOUT_H
#define SHEAR_LAYOUT_H

namespace shear
{
namespace layout
{
    struct Rect
    {
        int x, y, w, h;

        int Right() const { return x + w; }
        int Bottom() const { return y + h; }
    };

    /** What MulDiv(value, dpi, 96) does, written out so that a test that does
        not link against Windows can use the same arithmetic the dialog does.
        MulDiv rounds to nearest, and for the positive values in this table
        that is exactly this. */
    inline int Scale(int value, int dpi)
    {
        return static_cast<int>((static_cast<long long>(value) * dpi + 48) / 96);
    }

    inline Rect Scale(const Rect& r, int dpi)
    {
        const Rect out = { Scale(r.x, dpi), Scale(r.y, dpi),
                           Scale(r.w, dpi), Scale(r.h, dpi) };
        return out;
    }

    /** The client area. The window is sized to this and then adjusted outward
        for its frame. */
    const Rect kClient = { 0, 0, 432, 160 };

    /** The point size of the dialog font, scaled against 72 rather than 96
        because that is what a point is. */
    const int kFontPointSize = 9;

    enum Kind { kStatic, kSlider, kEdit, kCheckBox, kButton };

    struct Item
    {
        const char* name;
        Rect rect;
        Kind kind;
        bool focusable;   // reachable by Tab, and so needing a usable hit target
    };

    /** Index into kItems. The dialog builds its controls from the same table
        the test reads, so the two cannot drift apart. */
    enum Index
    {
        kShearLabel = 0, kShearSlider, kShearEdit, kShearDegree,
        kAxisLabel, kAxisSlider, kAxisEdit, kAxisDegree,
        kPreview, kReset, kCancel, kOk
    };

    const Item kItems[] = {
        { "shear label",   {  16, 18,  90, 18 }, kStatic,   false },
        { "shear slider",  { 110, 14, 220, 26 }, kSlider,   true  },
        { "shear edit",    { 340, 16,  60, 22 }, kEdit,     true  },
        { "shear degree",  { 404, 18,  14, 18 }, kStatic,   false },
        { "axis label",    {  16, 54,  90, 18 }, kStatic,   false },
        { "axis slider",   { 110, 50, 220, 26 }, kSlider,   true  },
        { "axis edit",     { 340, 52,  60, 22 }, kEdit,     true  },
        { "axis degree",   { 404, 54,  14, 18 }, kStatic,   false },
        { "preview",       {  16, 92,  90, 22 }, kCheckBox, true  },
        { "reset",         { 120, 92,  70, 24 }, kButton,   true  },
        { "cancel",        { 250, 92,  78, 24 }, kButton,   true  },
        { "ok",            { 338, 92,  78, 24 }, kButton,   true  }
    };

    const int kItemCount = static_cast<int>(sizeof(kItems) / sizeof(kItems[0]));
}
}

#endif
