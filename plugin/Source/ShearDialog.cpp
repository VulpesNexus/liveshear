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

//  ShearDialog.cpp -- a plain Win32 modal dialog, built at run time so the
//  plugin carries no dialog resource template.
//
//  Two rows, each a slider paired with an editable numeric field, plus a
//  Preview check box. Moving a slider writes the new values into the effect's
//  parameter dictionary and asks Illustrator to re-run the effect, so the
//  artwork updates under the dialog. Cancel puts the dictionary back the way it
//  was and re-runs once more, so nothing is left behind.
//
//  Every preview is computed from the parameters as they stand now, against art
//  the appearance pipeline rebuilds from the untouched source. Nothing here
//  ever transforms the previous preview.
//
//  Everything that touches text uses the wide-character Windows entry points.
//  The narrow ones convert through whatever code page the machine is set to,
//  and on a Japanese Windows this dialog's degree sign came out as two
//  half-width katakana -- a screen capture of the dialog is what caught it.
//  There is no code page involved below, so there is nothing left to get wrong.

#include "IllustratorSDK.h"
#include "ShearDialog.h"
#include "ShearEffect.h"
#include "ShearMath.h"
#include "ShearLayout.h"
#include "ShearTheme.h"
#include "LiveShearSuites.h"
#include "LiveShearID.h"
#include "ShearLog.h"

#ifdef WIN_ENV

#include <windows.h>
#include <commctrl.h>
#include <cstdlib>
#include <cmath>
#include <cwchar>
#include <iterator>
#include <string>
#include <sstream>
#include <locale>

#pragma comment(lib, "comctl32.lib")

namespace
{
    const int kIdShearSlider = 1001;
    const int kIdShearEdit   = 1002;
    const int kIdAxisSlider  = 1003;
    const int kIdAxisEdit    = 1004;
    const int kIdPreview     = 1005;
    const int kIdReset       = 1006;

    /** Sliders are integral, so both angles are carried in tenths of a degree. */
    const int kScale = 10;

    /** The shear field stops one degree short of vertical; ShearMath.h explains
        why, and SanitizeShearAngle enforces the same limit for values that
        never pass through this dialog at all. */
    const double kShearMin = -shear::kShearLimitDegrees;
    const double kShearMax =  shear::kShearLimitDegrees;
    const double kAxisMin  = -180.0;
    const double kAxisMax  =  180.0;

    /** U+00B0. Written as an escape rather than as the character so that the
        file's own encoding cannot come into it. */
    const wchar_t kDegreeSign = L'\x00B0';
    const wchar_t* const kDegreeLabel = L"\x00B0";

    const wchar_t* const kClassName = L"VulpesNexusShearDialog";
    bool gClassRegistered = false;
    HINSTANCE gClassInstance = nullptr;

    struct DialogData
    {
        ShearDialogState* state = nullptr;
        double entryShear = 0.0;
        double entryAxis = 0.0;
        bool committed = false;
        bool finished = false;
        bool updating = false;
        /** What was last written into the parameter dictionary, so that a
            preview which would change nothing does not ask Illustrator to
            re-render the artwork anyway. */
        double pushedShear = 0.0;
        double pushedAxis = 0.0;
        int dpi = 96;
        HFONT font = nullptr;
        HWND shearSlider = nullptr;
        HWND shearEdit = nullptr;
        HWND axisSlider = nullptr;
        HWND axisEdit = nullptr;
        HWND preview = nullptr;

        /** Illustrator's own dialog colors, read once when the window is
            created. The dialog is modal, so the host's brightness cannot
            change underneath it. */
        sheartheme::Theme theme;
        HBRUSH backBrush = nullptr;
        HBRUSH editBrush = nullptr;
        /** The mouse is over this control, so it draws lit. Tracked here
            because an owner-drawn button is told it is pushed but never that
            it is merely hovered. */
        int hot = 0;
    };

    /** Control identifiers travel to CreateWindow in the hMenu parameter.
        Widening through INT_PTR first keeps the conversion well defined on
        64-bit, where a bare cast from int to a pointer is a narrowing one in
        reverse. */
    HMENU ControlId(int id)
    {
        return reinterpret_cast<HMENU>(static_cast<INT_PTR>(id));
    }

    double Clamp(double v, double lo, double hi)
    {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    /** Formats to one decimal in the C locale, whatever locale the host has
        left the process in. */
    std::wstring Format(double v)
    {
        std::wostringstream o;
        o.imbue(std::locale::classic());
        o.setf(std::ios::fixed, std::ios::floatfield);
        o.precision(1);
        o << v;
        return o.str();
    }

    /** Reads a number out of whatever the user typed or pasted.

        An EDIT control carries no locale of its own, so both the full stop and
        the comma are accepted as the decimal separator; a degree sign and
        surrounding spaces are ignored, as is any trailing text. Parsing happens
        in the C locale explicitly rather than in whichever one the host has
        installed, so the same keystrokes mean the same angle on every
        machine. */
    bool ParseAngle(const wchar_t* text, double* value)
    {
        if (text == nullptr) return false;

        std::wstring cleaned;
        for (const wchar_t* p = text; *p != 0; ++p)
        {
            const wchar_t c = *p;
            if (c == L',') { cleaned.push_back(L'.'); continue; }
            if (c == L' ' || c == L'\t' || c == kDegreeSign) continue;
            cleaned.push_back(c);
        }
        if (cleaned.empty()) return false;

        _locale_t invariant = _create_locale(LC_NUMERIC, "C");
        if (invariant == nullptr) return false;
        wchar_t* end = nullptr;
        const double parsed = _wcstod_l(cleaned.c_str(), &end, invariant);
        _free_locale(invariant);

        if (end == cleaned.c_str()) return false;
        if (!(parsed == parsed)) return false;                   // NaN
        if (parsed > 1.0e12 || parsed < -1.0e12) return false;   // infinity, or nonsense
        *value = parsed;
        return true;
    }

    void SetEditValue(HWND edit, double v)
    {
        SetWindowTextW(edit, Format(v).c_str());
    }

    /** Writes the current angles into the live effect's parameter dictionary
        and asks Illustrator to re-run the effect from the unmodified source. */
    void PushPreview(DialogData* dd, double shearAngle, double axisAngle)
    {
        ShearDialogState* st = dd->state;
        if (!st->allowPreview || st->parameters == nullptr || st->context == nullptr) return;
        if (shearAngle == dd->pushedShear && axisAngle == dd->pushedAxis) return;
        dd->pushedShear = shearAngle;
        dd->pushedAxis = axisAngle;
        ShearEffect::WriteParameters(st->parameters,
                                     static_cast<AIReal>(shearAngle),
                                     static_cast<AIReal>(axisAngle));
        sAILiveEffect->UpdateParameters(st->context);
    }

    void Republish(DialogData* dd)
    {
        if (dd->state->previewEnabled)
            PushPreview(dd, dd->state->shearAngle, dd->state->axisAngle);
        else
            PushPreview(dd, dd->entryShear, dd->entryAxis);
    }

    void SyncFromSlider(DialogData* dd, bool isShear)
    {
        if (dd->updating) return;
        dd->updating = true;
        if (isShear)
        {
            const int pos = static_cast<int>(SendMessageW(dd->shearSlider, TBM_GETPOS, 0, 0));
            dd->state->shearAngle = static_cast<double>(pos) / kScale;
            SetEditValue(dd->shearEdit, dd->state->shearAngle);
        }
        else
        {
            const int pos = static_cast<int>(SendMessageW(dd->axisSlider, TBM_GETPOS, 0, 0));
            dd->state->axisAngle = static_cast<double>(pos) / kScale;
            SetEditValue(dd->axisEdit, dd->state->axisAngle);
        }
        dd->updating = false;
        Republish(dd);
    }

    /** Rounds to the resolution the dialog actually offers.

        The slider carries tenths of a degree and the fields show one decimal,
        so a tenth is what this dialog can express. Without rounding here the
        same typed number ends up as three different values: the slider rounds
        a half away from zero, the field's formatting rounds a half to even,
        and the state keeps the unrounded number until something re-reads the
        field and quietly replaces it with what is on screen. Typing 18.25 then
        committed 18.2 while the slider sat at 18.3.

        Rounding once, on the way in, means the number shown, the slider
        position, and the value stored are the same number. A script writing
        the parameter dictionary directly is not affected: the effect honours
        whatever it is given, to full precision. */
    double ToDialogResolution(double v)
    {
        // std::round takes a half away from zero, which is what std::lround
        // does for the slider; using the same one in both places is the point.
        return std::round(v * kScale) / kScale;
    }

    void ApplyValue(DialogData* dd, bool isShear, double v)
    {
        dd->updating = true;
        if (isShear)
        {
            v = ToDialogResolution(Clamp(v, kShearMin, kShearMax));
            dd->state->shearAngle = v;
            SendMessageW(dd->shearSlider, TBM_SETPOS, TRUE,
                         static_cast<LPARAM>(std::lround(v * kScale)));
            SetEditValue(dd->shearEdit, v);
        }
        else
        {
            // An axis angle outside the slider's range is still a valid angle,
            // so it is wrapped into the range rather than clipped to its end:
            // 200 degrees means the same shear as -160 and should show as -160,
            // where clamping to 180 would silently change the result.
            v = ToDialogResolution(shear::SanitizeAxisAngle(v));
            dd->state->axisAngle = v;
            SendMessageW(dd->axisSlider, TBM_SETPOS, TRUE,
                         static_cast<LPARAM>(std::lround(v * kScale)));
            SetEditValue(dd->axisEdit, v);
        }
        dd->updating = false;
        Republish(dd);
    }

    void SyncFromEdit(DialogData* dd, bool isShear)
    {
        if (dd->updating) return;
        const HWND field = isShear ? dd->shearEdit : dd->axisEdit;
        wchar_t buf[64] = { 0 };
        GetWindowTextW(field, buf, static_cast<int>(std::size(buf)));

        double v = 0.0;
        if (!ParseAngle(buf, &v))
        {
            // Unreadable text is not an error to complain about; the field just
            // goes back to the value that is actually in effect.
            dd->updating = true;
            SetEditValue(field, isShear ? dd->state->shearAngle : dd->state->axisAngle);
            dd->updating = false;
            return;
        }
        ApplyValue(dd, isShear, v);
    }

    /** Up and down arrows nudge the field, by ten with Shift held, the way
        Adobe's own numeric fields behave. */
    LRESULT CALLBACK EditSubclassProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp,
                                      UINT_PTR id, DWORD_PTR ref)
    {
        DialogData* dd = reinterpret_cast<DialogData*>(ref);
        if (msg == WM_KEYDOWN && dd != nullptr && (wp == VK_UP || wp == VK_DOWN))
        {
            const bool isShear = (id == kIdShearEdit);
            const double step = (GetKeyState(VK_SHIFT) < 0) ? 10.0 : 1.0;
            const double current = isShear ? dd->state->shearAngle : dd->state->axisAngle;
            ApplyValue(dd, isShear, current + (wp == VK_UP ? step : -step));
            SendMessageW(hwnd, EM_SETSEL, 0, -1);
            return 0;
        }
        if (msg == WM_NCDESTROY) RemoveWindowSubclass(hwnd, EditSubclassProc, id);
        return DefSubclassProc(hwnd, msg, wp, lp);
    }

    HWND MakeLabel(HWND parent, HINSTANCE inst, const wchar_t* text,
                   int x, int y, int w, int h)
    {
        return CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT,
                               x, y, w, h, parent, nullptr, inst, nullptr);
    }

    /** Dots per inch of the monitor the window is on, asked for in the way that
        works on the widest range of Windows versions: the per-monitor call when
        the running system has it, the system-wide one otherwise. */
    int DpiOf(HWND hwnd)
    {
        typedef UINT (WINAPI *GetDpiForWindowProc)(HWND);
        typedef UINT (WINAPI *GetDpiForSystemProc)(void);

        const HMODULE user32 = GetModuleHandleW(L"user32.dll");
        if (user32 != nullptr)
        {
            const GetDpiForWindowProc forWindow = reinterpret_cast<GetDpiForWindowProc>(
                reinterpret_cast<void*>(GetProcAddress(user32, "GetDpiForWindow")));
            if (forWindow != nullptr && hwnd != nullptr)
            {
                const UINT dpi = forWindow(hwnd);
                if (dpi >= 48) return static_cast<int>(dpi);
            }
            const GetDpiForSystemProc forSystem = reinterpret_cast<GetDpiForSystemProc>(
                reinterpret_cast<void*>(GetProcAddress(user32, "GetDpiForSystem")));
            if (forSystem != nullptr)
            {
                const UINT dpi = forSystem();
                if (dpi >= 48) return static_cast<int>(dpi);
            }
        }

        const HDC screen = GetDC(nullptr);
        if (screen != nullptr)
        {
            const int dpi = GetDeviceCaps(screen, LOGPIXELSX);
            ReleaseDC(nullptr, screen);
            if (dpi >= 48) return dpi;
        }
        return 96;
    }

    /** The standard UI typeface at nine points for this monitor's scaling. The
        metrics the system reports are already scaled for the system's own dots
        per inch, so only the face name is taken from them and the size is
        computed here. */
    HFONT MakeUiFont(int dpi)
    {
        NONCLIENTMETRICSW metrics;
        ZeroMemory(&metrics, sizeof(metrics));
        metrics.cbSize = sizeof(metrics);

        LOGFONTW font;
        ZeroMemory(&font, sizeof(font));
        if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0))
            font = metrics.lfMessageFont;
        else
            wcscpy_s(font.lfFaceName, L"Segoe UI");

        font.lfHeight = -MulDiv(shear::layout::kFontPointSize, dpi, 72);
        font.lfWidth = 0;
        return CreateFontIndirectW(&font);
    }

    void FillSolid(HDC dc, const RECT& rc, COLORREF color)
    {
        const HBRUSH brush = CreateSolidBrush(color);
        if (brush == nullptr) return;
        FillRect(dc, &rc, brush);
        DeleteObject(brush);
    }

    void FrameSolid(HDC dc, const RECT& rc, COLORREF color)
    {
        const HBRUSH brush = CreateSolidBrush(color);
        if (brush == nullptr) return;
        FrameRect(dc, &rc, brush);
        DeleteObject(brush);
    }

    /** One pixel at this monitor's scaling, so a border drawn on a 200% display
        is not a hairline the artwork swallows. */
    int Hairline(int dpi)
    {
        const int n = MulDiv(1, dpi, 96);
        return n < 1 ? 1 : n;
    }

    void InsetBy(RECT& rc, int n)
    {
        rc.left += n; rc.top += n; rc.right -= n; rc.bottom -= n;
    }

    /** Frames a rectangle with a border n pixels thick, from the outside in,
        because FrameRect only ever draws one pixel. */
    void FrameThick(HDC dc, RECT rc, COLORREF color, int n)
    {
        for (int i = 0; i < n; ++i) { FrameSolid(dc, rc, color); InsetBy(rc, 1); }
    }

    void DrawButtonText(HDC dc, HWND button, const RECT& rc, COLORREF color, HFONT font)
    {
        wchar_t text[64];
        text[0] = L'\0';
        GetWindowTextW(button, text, static_cast<int>(std::size(text)));

        const HGDIOBJ oldFont = font != nullptr ? SelectObject(dc, font) : nullptr;
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, color);
        RECT box = rc;
        DrawTextW(dc, text, -1, &box, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        if (oldFont != nullptr) SelectObject(dc, oldFont);
    }

    /** A push button in the host's colors: a flat face with a one-pixel
        border, which is what Illustrator's own buttons look like at every
        brightness. The default button is marked with the focus-ring color
        rather than by being a different shape. */
    void DrawPushButton(DialogData* dd, const DRAWITEMSTRUCT* di)
    {
        const sheartheme::Theme& t = dd->theme;
        const bool disabled = (di->itemState & ODS_DISABLED) != 0;
        const bool pressed = (di->itemState & ODS_SELECTED) != 0;
        const bool focused = (di->itemState & ODS_FOCUS) != 0;
        const bool hot = dd->hot == static_cast<int>(di->CtlID);
        const bool isDefault = di->CtlID == IDOK;

        COLORREF face = t.control;
        if (disabled) face = t.background;
        else if (pressed) face = t.controlPressed;
        else if (hot) face = t.controlHot;

        RECT rc = di->rcItem;
        FillSolid(di->hDC, rc, face);

        const int line = Hairline(dd->dpi);
        COLORREF edge = t.border;
        if (isDefault && !disabled) edge = t.focusRing;
        FrameThick(di->hDC, rc, edge, line);

        if (focused && !disabled)
        {
            RECT ring = rc;
            InsetBy(ring, line * 2);
            FrameThick(di->hDC, ring, t.focusRing, line);
        }

        DrawButtonText(di->hDC, di->hwndItem, rc,
                       disabled ? t.disabledText : t.text, dd->font);
    }

    /** The Preview check box. Owner-drawn like the buttons, because a stock
        check box paints its own white square and there is no message that
        recolours it. The tick is two strokes rather than a font glyph, so it
        cannot come out as a missing-character box on a machine without the
        symbol face. */
    void DrawCheckBox(DialogData* dd, const DRAWITEMSTRUCT* di)
    {
        const sheartheme::Theme& t = dd->theme;
        const bool disabled = (di->itemState & ODS_DISABLED) != 0;
        const bool focused = (di->itemState & ODS_FOCUS) != 0;
        const bool hot = dd->hot == static_cast<int>(di->CtlID);
        const bool checked = dd->state != nullptr && dd->state->previewEnabled;

        RECT rc = di->rcItem;
        FillSolid(di->hDC, rc, t.background);

        const int line = Hairline(dd->dpi);
        const int side = MulDiv(13, dd->dpi, 96);
        RECT box;
        box.left = rc.left;
        box.top = rc.top + (rc.bottom - rc.top - side) / 2;
        box.right = box.left + side;
        box.bottom = box.top + side;

        FillSolid(di->hDC, box, disabled ? t.background : t.editBackground);
        FrameThick(di->hDC, box, (hot && !disabled) ? t.focusRing : t.border, line);

        if (checked)
        {
            const COLORREF ink = disabled ? t.disabledText : t.editText;
            const HPEN pen = CreatePen(PS_SOLID, line * 2, ink);
            if (pen != nullptr)
            {
                const HGDIOBJ oldPen = SelectObject(di->hDC, pen);
                const int w = box.right - box.left;
                const POINT pts[3] = {
                    { box.left + w / 4,     box.top + w / 2 },
                    { box.left + w / 2 - line, box.bottom - w / 3 },
                    { box.right - w / 5,    box.top + w / 4 }
                };
                Polyline(di->hDC, pts, 3);
                SelectObject(di->hDC, oldPen);
                DeleteObject(pen);
            }
        }

        wchar_t text[64];
        text[0] = L'\0';
        GetWindowTextW(di->hwndItem, text, static_cast<int>(std::size(text)));
        RECT label = rc;
        label.left = box.right + MulDiv(6, dd->dpi, 96);

        const HGDIOBJ oldFont = dd->font != nullptr ? SelectObject(di->hDC, dd->font) : nullptr;
        SetBkMode(di->hDC, TRANSPARENT);
        SetTextColor(di->hDC, disabled ? t.disabledText : t.text);
        DrawTextW(di->hDC, text, -1, &label, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
        if (oldFont != nullptr) SelectObject(di->hDC, oldFont);

        if (focused && !disabled)
        {
            RECT ring = rc;
            InsetBy(ring, line);
            FrameThick(di->hDC, ring, t.focusRing, line);
        }
    }

    /** The trackbars. A stock trackbar paints a light channel and a chrome
        thumb from the visual styles, neither of which can be recoloured by a
        message, so the two parts that show are drawn here instead. */
    LRESULT DrawTrackbar(DialogData* dd, NMCUSTOMDRAW* cd)
    {
        const sheartheme::Theme& t = dd->theme;

        if (cd->dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
        if (cd->dwDrawStage != CDDS_ITEMPREPAINT) return CDRF_DODEFAULT;

        const int line = Hairline(dd->dpi);
        const bool enabled = IsWindowEnabled(cd->hdr.hwndFrom) != FALSE;

        if (cd->dwItemSpec == TBCD_CHANNEL)
        {
            RECT rc = cd->rc;
            // The stock channel rectangle is taller than the groove it draws.
            const int thickness = MulDiv(3, dd->dpi, 96);
            const int middle = (rc.top + rc.bottom) / 2;
            rc.top = middle - thickness / 2;
            rc.bottom = rc.top + thickness;
            FillSolid(cd->hdc, rc, enabled ? t.border : t.background);
            return CDRF_SKIPDEFAULT;
        }

        if (cd->dwItemSpec == TBCD_THUMB)
        {
            RECT rc = cd->rc;
            const bool hot = dd->hot == static_cast<int>(GetDlgCtrlID(cd->hdr.hwndFrom));
            FillSolid(cd->hdc, rc, enabled ? (hot ? t.controlHot : t.control) : t.background);
            FrameThick(cd->hdc, rc, enabled ? t.focusRing : t.border, line);
            return CDRF_SKIPDEFAULT;
        }

        if (cd->dwItemSpec == TBCD_TICS) return CDRF_SKIPDEFAULT;
        return CDRF_DODEFAULT;
    }

    /** Which control the pointer is over, so buttons light up under it the way
        a stock button does through the visual styles. An owner-drawn control is
        never told it is merely hovered, and the parent does not see mouse
        movement over its children, so each control reports for itself. */
    LRESULT CALLBACK HoverSubclassProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp,
                                       UINT_PTR id, DWORD_PTR ref)
    {
        DialogData* dd = reinterpret_cast<DialogData*>(ref);

        if (msg == WM_MOUSEMOVE && dd != nullptr)
        {
            if (dd->hot != static_cast<int>(id))
            {
                const HWND was = dd->hot != 0 ? GetDlgItem(GetParent(hwnd), dd->hot) : nullptr;
                dd->hot = static_cast<int>(id);
                if (was != nullptr) InvalidateRect(was, nullptr, TRUE);
                InvalidateRect(hwnd, nullptr, TRUE);

                // Asking for one leave message; without it the control stays
                // lit after the pointer has gone somewhere else entirely.
                TRACKMOUSEEVENT tme;
                ZeroMemory(&tme, sizeof(tme));
                tme.cbSize = sizeof(tme);
                tme.dwFlags = TME_LEAVE;
                tme.hwndTrack = hwnd;
                TrackMouseEvent(&tme);
            }
        }
        else if (msg == WM_MOUSELEAVE && dd != nullptr)
        {
            if (dd->hot == static_cast<int>(id))
            {
                dd->hot = 0;
                InvalidateRect(hwnd, nullptr, TRUE);
            }
        }
        else if (msg == WM_NCDESTROY)
        {
            RemoveWindowSubclass(hwnd, HoverSubclassProc, id);
        }

        return DefSubclassProc(hwnd, msg, wp, lp);
    }

    LRESULT CALLBACK DialogProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
    {
        DialogData* dd = reinterpret_cast<DialogData*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

        switch (msg)
        {
            case WM_CREATE:
            {
                CREATESTRUCTW* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
                dd = static_cast<DialogData*>(cs->lpCreateParams);
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(dd));
                const HINSTANCE inst = cs->hInstance;

                dd->dpi = DpiOf(hwnd);
                const int dpi = dd->dpi;

                // Ask the host what it looks like before building anything, so
                // every control is created into a known set of colors rather
                // than repainted out of the system gray afterwards.
                dd->theme = sheartheme::Read();
                dd->backBrush = CreateSolidBrush(dd->theme.background);
                dd->editBrush = CreateSolidBrush(dd->theme.editBackground);
                sheartheme::ApplyTitleBar(hwnd, dd->theme.dark);
                // Every control's box comes from the table in ShearLayout.h,
                // which is also what the layout test reads, so the dialog and
                // the thing that checks it cannot disagree.
                #define R(which) const shear::layout::Rect box = \
                    shear::layout::Scale(shear::layout::kItems[shear::layout::which].rect, dpi)

                { R(kShearLabel);
                  MakeLabel(hwnd, inst, L"Shear Angle", box.x, box.y, box.w, box.h); }
                { R(kShearSlider);
                dd->shearSlider = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdShearSlider), inst, nullptr); }
                SendMessageW(dd->shearSlider, TBM_SETRANGE, TRUE,
                             MAKELPARAM(static_cast<int>(kShearMin * kScale),
                                        static_cast<int>(kShearMax * kScale)));
                SendMessageW(dd->shearSlider, TBM_SETPOS, TRUE,
                             static_cast<LPARAM>(std::lround(dd->state->shearAngle * kScale)));
                { R(kShearEdit);
                dd->shearEdit = CreateWindowExW(0, L"EDIT", L"",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdShearEdit), inst, nullptr); }
                SetEditValue(dd->shearEdit, dd->state->shearAngle);
                { R(kShearDegree);
                  MakeLabel(hwnd, inst, kDegreeLabel, box.x, box.y, box.w, box.h); }

                { R(kAxisLabel);
                  MakeLabel(hwnd, inst, L"Axis Angle", box.x, box.y, box.w, box.h); }
                { R(kAxisSlider);
                dd->axisSlider = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdAxisSlider), inst, nullptr); }
                SendMessageW(dd->axisSlider, TBM_SETRANGE, TRUE,
                             MAKELPARAM(static_cast<int>(kAxisMin * kScale),
                                        static_cast<int>(kAxisMax * kScale)));
                SendMessageW(dd->axisSlider, TBM_SETPOS, TRUE,
                             static_cast<LPARAM>(std::lround(dd->state->axisAngle * kScale)));
                { R(kAxisEdit);
                dd->axisEdit = CreateWindowExW(0, L"EDIT", L"",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdAxisEdit), inst, nullptr); }
                SetEditValue(dd->axisEdit, dd->state->axisAngle);
                { R(kAxisDegree);
                  MakeLabel(hwnd, inst, kDegreeLabel, box.x, box.y, box.w, box.h); }

                { R(kPreview);
                dd->preview = CreateWindowExW(0, L"BUTTON", L"Preview",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdPreview), inst, nullptr); }
                EnableWindow(dd->preview, dd->state->allowPreview ? TRUE : FALSE);

                { R(kReset);
                CreateWindowExW(0, L"BUTTON", L"Reset",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(kIdReset), inst, nullptr); }
                { R(kCancel);
                CreateWindowExW(0, L"BUTTON", L"Cancel",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(IDCANCEL), inst, nullptr); }
                { R(kOk);
                CreateWindowExW(0, L"BUTTON", L"OK",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                    box.x, box.y, box.w, box.h, hwnd,
                    ControlId(IDOK), inst, nullptr); }
                #undef R

                // Give every control the standard UI font instead of the
                // 1980s system font CreateWindow hands out by default.
                dd->font = MakeUiFont(dd->dpi);
                if (dd->font != nullptr)
                {
                    EnumChildWindows(hwnd, [](HWND child, LPARAM font) -> BOOL {
                        SendMessageW(child, WM_SETFONT, static_cast<WPARAM>(font), TRUE);
                        return TRUE;
                    }, reinterpret_cast<LPARAM>(dd->font));
                }

                SetWindowSubclass(dd->shearEdit, EditSubclassProc, kIdShearEdit,
                                  reinterpret_cast<DWORD_PTR>(dd));
                SetWindowSubclass(dd->axisEdit, EditSubclassProc, kIdAxisEdit,
                                  reinterpret_cast<DWORD_PTR>(dd));

                // Everything that lights up under the pointer.
                {
                    const int hoverIds[] = { kIdPreview, kIdReset, IDCANCEL, IDOK,
                                             kIdShearSlider, kIdAxisSlider };
                    for (size_t i = 0; i < std::size(hoverIds); ++i)
                    {
                        const HWND control = GetDlgItem(hwnd, hoverIds[i]);
                        if (control != nullptr)
                            SetWindowSubclass(control, HoverSubclassProc,
                                              static_cast<UINT_PTR>(hoverIds[i]),
                                              reinterpret_cast<DWORD_PTR>(dd));
                    }
                }

                Republish(dd);
                return 0;
            }

            case WM_ERASEBKGND:
                if (dd != nullptr && dd->backBrush != nullptr)
                {
                    RECT rc;
                    GetClientRect(hwnd, &rc);
                    FillRect(reinterpret_cast<HDC>(wp), &rc, dd->backBrush);
                    return 1;
                }
                break;

            case WM_PAINT:
                // The edit fields lost their system bevel, which could not be
                // recoloured, so their border is drawn here in the host's own
                // line color -- outside each field, on the dialog's face.
                if (dd != nullptr)
                {
                    PAINTSTRUCT ps;
                    const HDC dc = BeginPaint(hwnd, &ps);
                    const int line = Hairline(dd->dpi);
                    const HWND fields[2] = { dd->shearEdit, dd->axisEdit };
                    for (int i = 0; i < 2; ++i)
                    {
                        if (fields[i] == nullptr) continue;
                        RECT rc;
                        GetWindowRect(fields[i], &rc);
                        MapWindowPoints(nullptr, hwnd, reinterpret_cast<POINT*>(&rc), 2);
                        InsetBy(rc, -line);
                        const bool focused = GetFocus() == fields[i];
                        FrameThick(dc, rc,
                                   focused ? dd->theme.focusRing : dd->theme.border, line);
                    }
                    EndPaint(hwnd, &ps);
                    return 0;
                }
                break;

            case WM_CTLCOLORSTATIC:
                // Labels and both trackbars come through here.
                if (dd != nullptr && dd->backBrush != nullptr)
                {
                    SetBkMode(reinterpret_cast<HDC>(wp), TRANSPARENT);
                    SetTextColor(reinterpret_cast<HDC>(wp),
                                 IsWindowEnabled(reinterpret_cast<HWND>(lp))
                                     ? dd->theme.text : dd->theme.disabledText);
                    SetBkColor(reinterpret_cast<HDC>(wp), dd->theme.background);
                    return reinterpret_cast<LRESULT>(dd->backBrush);
                }
                break;

            case WM_CTLCOLOREDIT:
                if (dd != nullptr && dd->editBrush != nullptr)
                {
                    SetTextColor(reinterpret_cast<HDC>(wp), dd->theme.editText);
                    SetBkColor(reinterpret_cast<HDC>(wp), dd->theme.editBackground);
                    return reinterpret_cast<LRESULT>(dd->editBrush);
                }
                break;

            case WM_DRAWITEM:
                if (dd != nullptr)
                {
                    const DRAWITEMSTRUCT* di = reinterpret_cast<const DRAWITEMSTRUCT*>(lp);
                    if (di->CtlType == ODT_BUTTON)
                    {
                        if (di->CtlID == kIdPreview) DrawCheckBox(dd, di);
                        else DrawPushButton(dd, di);
                        return TRUE;
                    }
                }
                break;

            case WM_NOTIFY:
                if (dd != nullptr)
                {
                    NMHDR* hdr = reinterpret_cast<NMHDR*>(lp);
                    if (hdr != nullptr && hdr->code == NM_CUSTOMDRAW &&
                        (hdr->hwndFrom == dd->shearSlider || hdr->hwndFrom == dd->axisSlider))
                    {
                        return DrawTrackbar(dd, reinterpret_cast<NMCUSTOMDRAW*>(lp));
                    }
                }
                break;

            case WM_HSCROLL:
                if (dd)
                {
                    const HWND from = reinterpret_cast<HWND>(lp);
                    if (from == dd->shearSlider) SyncFromSlider(dd, true);
                    else if (from == dd->axisSlider) SyncFromSlider(dd, false);
                }
                return 0;

            case WM_COMMAND:
                if (dd == nullptr) break;
                switch (LOWORD(wp))
                {
                    case kIdShearEdit:
                        if (HIWORD(wp) == EN_KILLFOCUS) SyncFromEdit(dd, true);
                        return 0;
                    case kIdAxisEdit:
                        if (HIWORD(wp) == EN_KILLFOCUS) SyncFromEdit(dd, false);
                        return 0;
                    case kIdPreview:
                        dd->state->previewEnabled = !dd->state->previewEnabled;
                        InvalidateRect(dd->preview, nullptr, TRUE);
                        Republish(dd);
                        return 0;
                    case kIdReset:
                        dd->updating = true;
                        dd->state->shearAngle = 0.0;
                        dd->state->axisAngle = 0.0;
                        SendMessageW(dd->shearSlider, TBM_SETPOS, TRUE, 0);
                        SendMessageW(dd->axisSlider, TBM_SETPOS, TRUE, 0);
                        SetEditValue(dd->shearEdit, 0.0);
                        SetEditValue(dd->axisEdit, 0.0);
                        dd->updating = false;
                        Republish(dd);
                        return 0;
                    case IDOK:
                        SyncFromEdit(dd, true);
                        SyncFromEdit(dd, false);
                        dd->committed = true;
                        DestroyWindow(hwnd);
                        return 0;
                    case IDCANCEL:
                        dd->committed = false;
                        DestroyWindow(hwnd);
                        return 0;
                    default:
                        break;
                }
                break;

            case WM_CLOSE:
                // The title bar's close button means the same as Cancel.
                if (dd) dd->committed = false;
                DestroyWindow(hwnd);
                return 0;

            case WM_DESTROY:
                // The font is not deleted here: DestroyWindow sends this to the
                // parent before it destroys the children, which are still
                // holding it. RunShearDialog deletes it once the loop is over.
                if (dd) dd->finished = true;
                // Wake the modal loop below without posting WM_QUIT, which
                // belongs to the application and not to one dialog.
                PostMessageW(nullptr, WM_NULL, 0, 0);
                return 0;

            default:
                break;
        }
        return DefWindowProcW(hwnd, msg, wp, lp);
    }

    HINSTANCE OwnInstance()
    {
        HMODULE mod = nullptr;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(&OwnInstance), &mod);
        return reinterpret_cast<HINSTANCE>(mod);
    }
}

bool RunShearDialog(ShearDialogState& state)
{
    const HINSTANCE inst = OwnInstance();

    INITCOMMONCONTROLSEX icc;
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_BAR_CLASSES | ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icc);

    if (!gClassRegistered)
    {
        WNDCLASSEXW wc;
        ZeroMemory(&wc, sizeof(wc));
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = DialogProc;
        wc.hInstance = inst;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
        wc.lpszClassName = kClassName;
        if (!RegisterClassExW(&wc))
        {
            std::ostringstream o;
            o << "dialog: RegisterClassEx failed, GetLastError=" << GetLastError();
            shearlog::Write(o.str());
            return false;
        }
        gClassRegistered = true;
        gClassInstance = inst;
    }

    HWND parent = nullptr;
    AIWindowRef appWindow = nullptr;
    if (!sAIAppContext->GetPlatformAppWindow(&appWindow))
        parent = reinterpret_cast<HWND>(appWindow);

    DialogData dd;
    dd.state = &state;
    dd.entryShear = state.shearAngle;
    dd.entryAxis = state.axisAngle;
    // The dictionary already holds these, so the first preview has nothing to
    // do and the artwork is not re-rendered just because the dialog opened.
    dd.pushedShear = state.shearAngle;
    dd.pushedAxis = state.axisAngle;

    const int dpi = DpiOf(parent);
    const shear::layout::Rect client = shear::layout::Scale(shear::layout::kClient, dpi);
    RECT rc = { 0, 0, client.w, client.h };
    AdjustWindowRectEx(&rc, WS_CAPTION | WS_SYSMENU, FALSE, WS_EX_DLGMODALFRAME);

    const HWND hwnd = CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT,
        kClassName, L"Shear",
        WS_POPUPWINDOW | WS_CAPTION | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top,
        parent, nullptr, inst, &dd);
    if (hwnd == nullptr)
    {
        std::ostringstream o;
        o << "dialog: CreateWindowEx failed, GetLastError=" << GetLastError()
          << " parent=" << (parent ? "yes" : "no");
        shearlog::Write(o.str());
        return false;
    }
    shearlog::Write("dialog: opened");

    if (parent) EnableWindow(parent, FALSE);
    SetFocus(dd.shearEdit);

    MSG msg;
    while (!dd.finished)
    {
        if (!GetMessageW(&msg, nullptr, 0, 0))
        {
            // The application itself is quitting. Put the message back for
            // Illustrator's own loop rather than swallowing it here, and close
            // the dialog as a cancel.
            PostQuitMessage(static_cast<int>(msg.wParam));
            dd.committed = false;
            if (IsWindow(hwnd)) DestroyWindow(hwnd);
            break;
        }
        if (dd.finished) break;
        // IsDialogMessage treats the arrow keys as navigation between controls,
        // which would swallow the up and down nudges before the numeric fields
        // ever see them.
        const bool nudge = msg.message == WM_KEYDOWN &&
                           (msg.wParam == VK_UP || msg.wParam == VK_DOWN) &&
                           (msg.hwnd == dd.shearEdit || msg.hwnd == dd.axisEdit);

        // Enter used to be handled for free, because OK carried
        // BS_DEFPUSHBUTTON and IsDialogMessage looks for it. That style lives
        // in the same bits as BS_OWNERDRAW and a button cannot have both, so
        // the key is routed here instead: to the push button that has the
        // focus if one does, and to OK otherwise, which is what a stock dialog
        // does with it.
        if (msg.message == WM_KEYDOWN && msg.wParam == VK_RETURN)
        {
            const HWND focus = GetFocus();
            const int focused = focus != nullptr ? GetDlgCtrlID(focus) : 0;
            const bool onButton = focused == kIdReset || focused == IDCANCEL || focused == IDOK;
            const int send = onButton ? focused : IDOK;
            SendMessageW(hwnd, WM_COMMAND,
                         MAKEWPARAM(send, BN_CLICKED),
                         reinterpret_cast<LPARAM>(onButton ? focus : nullptr));
            continue;
        }

        if (nudge || !IsDialogMessageW(hwnd, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    // Same reason as the font: the controls were still holding these while
    // they drew, and they are gone only once the loop is over.
    if (dd.font != nullptr) { DeleteObject(dd.font); dd.font = nullptr; }
    if (dd.backBrush != nullptr) { DeleteObject(dd.backBrush); dd.backBrush = nullptr; }
    if (dd.editBrush != nullptr) { DeleteObject(dd.editBrush); dd.editBrush = nullptr; }

    if (parent)
    {
        EnableWindow(parent, TRUE);
        SetForegroundWindow(parent);
    }

    {
        std::ostringstream o;
        o.imbue(std::locale::classic());
        o << "dialog: closed, committed=" << (dd.committed ? 1 : 0)
          << " shear=" << state.shearAngle << " axis=" << state.axisAngle
          << " dpi=" << dd.dpi;
        shearlog::Write(o.str());
    }

    if (!dd.committed)
    {
        state.shearAngle = dd.entryShear;
        state.axisAngle = dd.entryAxis;
        if (state.allowPreview && state.parameters && state.context)
        {
            ShearEffect::WriteParameters(state.parameters,
                                         static_cast<AIReal>(state.shearAngle),
                                         static_cast<AIReal>(state.axisAngle));
            sAILiveEffect->UpdateParameters(state.context);
        }
    }
    return dd.committed;
}

void ShutdownShearDialog()
{
    if (!gClassRegistered) return;
    UnregisterClassW(kClassName, gClassInstance);
    gClassRegistered = false;
    gClassInstance = nullptr;
}

#else  // !WIN_ENV

bool RunShearDialog(ShearDialogState&)
{
    return false;
}

void ShutdownShearDialog()
{
}

#endif
