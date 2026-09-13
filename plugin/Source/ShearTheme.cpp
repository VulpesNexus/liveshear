//  ShearTheme.cpp -- reading Illustrator's own dialog colors.

#include "IllustratorSDK.h"
#include "ShearTheme.h"
#include "LiveShearSuites.h"
#include "ShearLog.h"

#ifdef WIN_ENV

#include <sstream>

namespace
{
    /** The suite hands back components as reals from zero to one. */
    BYTE Channel(AIReal v)
    {
        const double scaled = static_cast<double>(v) * 255.0 + 0.5;
        if (scaled <= 0.0) return 0;
        if (scaled >= 255.0) return 255;
        return static_cast<BYTE>(scaled);
    }

    COLORREF ToColorRef(const AIUIThemeColor& c)
    {
        return RGB(Channel(c.red), Channel(c.green), Channel(c.blue));
    }

    /** Moves a color towards white or towards black by a fixed number of
        levels. Taking the direction from the theme rather than from the color
        keeps a button face distinguishable at every brightness: on a dark
        theme a raised control is lighter than the dialog, on a light one it is
        darker, and the medium settings in between never invert. */
    COLORREF Shift(COLORREF base, int amount, bool lighter)
    {
        int r = GetRValue(base);
        int g = GetGValue(base);
        int b = GetBValue(base);
        const int delta = lighter ? amount : -amount;
        r += delta; g += delta; b += delta;
        if (r < 0) r = 0; if (r > 255) r = 255;
        if (g < 0) g = 0; if (g > 255) g = 255;
        if (b < 0) b = 0; if (b > 255) b = 255;
        return RGB(r, g, b);
    }

    COLORREF Blend(COLORREF a, COLORREF b, double t)
    {
        const double s = 1.0 - t;
        return RGB(
            static_cast<BYTE>(GetRValue(a) * s + GetRValue(b) * t + 0.5),
            static_cast<BYTE>(GetGValue(a) * s + GetGValue(b) * t + 0.5),
            static_cast<BYTE>(GetBValue(a) * s + GetBValue(b) * t + 0.5));
    }

    sheartheme::Theme FromSystem()
    {
        sheartheme::Theme t;
        t.fromHost = false;
        t.dark = false;
        t.background = GetSysColor(COLOR_BTNFACE);
        t.text = GetSysColor(COLOR_BTNTEXT);
        t.editText = GetSysColor(COLOR_WINDOWTEXT);
        t.editBackground = GetSysColor(COLOR_WINDOW);
        t.border = GetSysColor(COLOR_3DSHADOW);
        t.focusRing = GetSysColor(COLOR_HOTLIGHT);
        t.control = GetSysColor(COLOR_BTNFACE);
        t.controlHot = Shift(t.control, 12, true);
        t.controlPressed = Shift(t.control, 12, false);
        t.disabledText = GetSysColor(COLOR_GRAYTEXT);
        return t;
    }
}

namespace sheartheme
{
    Theme Read()
    {
        // Acquired for the plugin's lifetime as an optional suite, so it is
        // null exactly when the host does not offer it.
        AIUIThemeSuite* const suite = sAIUITheme;
        if (suite == nullptr || suite->GetUIThemeColor == nullptr)
        {
            shearlog::Write("theme: the host has no UI theme suite; using system colors");
            return FromSystem();
        }

        Theme t;
        bool ok = true;

        // kAIUIThemeSelectorDialog rather than the panel theme: Illustrator
        // draws the two at different shades, and this is a dialog.
        struct Wanted { AIUIComponentColor which; COLORREF* into; };
        const Wanted wanted[] = {
            { kAIUIComponentColorBackground,       &t.background },
            { kAIUIComponentColorText,             &t.text },
            { kAIUIComponentColorEditText,         &t.editText },
            { kAIUIComponentColorEditTextBackground, &t.editBackground },
            { kAIUIComponentColorBorder,           &t.border },
            { kAIUIComponentColorFocusRing,        &t.focusRing },
        };

        for (size_t i = 0; i < sizeof(wanted) / sizeof(wanted[0]); ++i)
        {
            AIUIThemeColor c;
            const AIErr err = suite->GetUIThemeColor(
                kAIUIThemeSelectorDialog, wanted[i].which, c);
            if (err != kNoErr) { ok = false; break; }
            *(wanted[i].into) = ToColorRef(c);
        }

        if (ok && suite->IsUIThemeDark != nullptr)
            t.dark = suite->IsUIThemeDark() ? true : false;

        if (!ok)
        {
            shearlog::Write("theme: the host declined a color; using system colors");
            return FromSystem();
        }

        t.fromHost = true;
        t.control = Shift(t.background, 14, t.dark);
        t.controlHot = Shift(t.background, 26, t.dark);
        t.controlPressed = Shift(t.background, 8, !t.dark);
        t.disabledText = Blend(t.text, t.background, 0.55);

        {
            std::ostringstream o;
            o << "theme: from host, dark=" << (t.dark ? 1 : 0)
              << " background=" << std::hex << static_cast<unsigned>(t.background)
              << " text=" << static_cast<unsigned>(t.text);
            shearlog::Write(o.str());
        }
        return t;
    }

    void ApplyTitleBar(HWND hwnd, bool dark)
    {
        typedef HRESULT (WINAPI *SetAttrProc)(HWND, DWORD, LPCVOID, DWORD);

        // Loaded by name rather than linked, so the plugin still depends on
        // nothing a machine that can start Illustrator does not already have.
        const HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
        if (dwm == nullptr) return;

        const SetAttrProc setAttr = reinterpret_cast<SetAttrProc>(
            reinterpret_cast<void*>(GetProcAddress(dwm, "DwmSetWindowAttribute")));
        if (setAttr != nullptr)
        {
            const BOOL on = dark ? TRUE : FALSE;
            // 20 is the documented attribute. Windows 10 builds between 17763
            // and 18985 used 19 for the same thing and ignore 20, so both are
            // offered and whichever the running system understands takes.
            setAttr(hwnd, 20, &on, sizeof(on));
            setAttr(hwnd, 19, &on, sizeof(on));
        }
        FreeLibrary(dwm);
    }
}

#endif // WIN_ENV

// End ShearTheme.cpp
