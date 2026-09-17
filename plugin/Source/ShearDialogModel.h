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

//  ShearDialogModel.h -- the decisions the dialog makes that need no window:
//  which axis button an angle selects, what a button stands for, and which
//  values the dialog opens with.
//
//  Split out for the same reason as ShearLayout.h: tools/mathtest checks these
//  without Illustrator and without Windows.

#ifndef SHEAR_DIALOG_MODEL_H
#define SHEAR_DIALOG_MODEL_H

namespace shear
{
    /** The three axis choices of Illustrator's own Object > Transform > Shear
        dialog. None of them is stored. Illustrator's Horizontal and Vertical
        buttons only set its axis angle to 0 and 90 degrees, and these do the
        same, so a document edited with them holds an axis angle like any other
        and an older build reads it unchanged. */
    enum AxisMode
    {
        kAxisHorizontal = 0,
        kAxisVertical,
        kAxisAngle
    };

    const double kHorizontalAxis = 0.0;
    const double kVerticalAxis = 90.0;

    /** The button that is selected when the dialog opens on an axis angle.

        Only the two exact angles name a button. An axis of -90 shears exactly
        like one of 90, and 180 like 0, but opening those under Vertical or
        Horizontal would make OK rewrite the stored number without anything
        having been touched. They open under Angle, as they are. */
    inline AxisMode AxisModeOf(double axisDegrees)
    {
        if (axisDegrees == kHorizontalAxis) return kAxisHorizontal;
        if (axisDegrees == kVerticalAxis) return kAxisVertical;
        return kAxisAngle;
    }

    /** The axis angle a button stands for. Angle stands for whatever it held
        when it was last selected, so clicking Horizontal to compare and then
        Angle again gives back a typed 37 degrees instead of losing it. */
    inline double AxisOfMode(AxisMode mode, double angleModeAxis)
    {
        switch (mode)
        {
            case kAxisHorizontal: return kHorizontalAxis;
            case kAxisVertical:   return kVerticalAxis;
            default:              return angleModeAxis;
        }
    }

    /** The values the dialog last committed, for as long as Illustrator runs.

        Kept in memory rather than in the preferences file because that is where
        Illustrator keeps its own: its preferences file holds whether each
        transform dialog's Preview box was ticked, and no angle for any of
        them. */
    struct LastUsed
    {
        bool known = false;
        double shearAngle = 0.0;
        double axisAngle = 0.0;
    };

    /** The values the dialog opens with.

        An effect being edited from the Appearance panel opens with its own
        values, because those are what the artwork shows. A new one opens with
        the values committed last, and with its stored values -- the defaults --
        only when nothing has been committed yet. */
    inline void OpeningValues(bool isNewInstance, const LastUsed& last,
                              double storedShear, double storedAxis,
                              double* shearAngle, double* axisAngle)
    {
        if (isNewInstance && last.known)
        {
            *shearAngle = last.shearAngle;
            *axisAngle = last.axisAngle;
        }
        else
        {
            *shearAngle = storedShear;
            *axisAngle = storedAxis;
        }
    }
}

#endif // SHEAR_DIALOG_MODEL_H
