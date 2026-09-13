//  ShearTheme.h -- the colours Illustrator is currently drawing its own
//  dialogs with.
//
//  A plain Win32 dialog is light grey with black text whatever the host looks
//  like, which is wrong three times out of four: Illustrator's interface has
//  four brightness settings and the darkest is the default. The host will say
//  what it is using, so the dialog asks instead of guessing, and asks about
//  dialogs specifically rather than panels, which are a different shade.

#ifndef __SHEARTHEME_H__
#define __SHEARTHEME_H__

#ifdef WIN_ENV

#include <windows.h>

namespace sheartheme
{
    struct Theme
    {
        /** False when the host could not be asked, in which case everything
            below came from the system colours instead and the dialog will
            look like an ordinary Windows one. That is the honest fallback:
            it is better than painting a guessed dark grey over a light host. */
        bool fromHost = false;
        bool dark = false;

        // Straight from the host.
        COLORREF background = 0;
        COLORREF text = 0;
        COLORREF editText = 0;
        COLORREF editBackground = 0;
        COLORREF border = 0;
        COLORREF focusRing = 0;

        // Derived. The suite has no colour for the face of a raised button, so
        // these are the dialog background moved away from itself by an amount
        // that reads the same on a dark theme and a light one.
        COLORREF control = 0;
        COLORREF controlHot = 0;
        COLORREF controlPressed = 0;
        COLORREF disabledText = 0;
    };

    /** Reads the theme now. The dialog is modal, so the brightness cannot
        change while it is open and there is nothing to keep up to date. */
    Theme Read();

    /** Asks the window manager to draw this window's title bar dark, on the
        Windows versions that can. Without it a dark dialog wears a white
        caption, which looks worse than not theming it at all. */
    void ApplyTitleBar(HWND hwnd, bool dark);
}

#endif // WIN_ENV

#endif // __SHEARTHEME_H__
