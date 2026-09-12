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

#include "IllustratorSDK.h"
#include "ShearDialog.h"
#include "ShearEffect.h"
#include "ShearMath.h"
#include "LiveShearSuites.h"
#include "LiveShearID.h"
#include "ShearLog.h"

#ifdef WIN_ENV

#include <windows.h>
#include <commctrl.h>
#include <cstdlib>
#include <cmath>
#include <cstring>
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

    const char* const kClassName = "VulpesNexusShearDialog";
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
    std::string Format(double v)
    {
        std::ostringstream o;
        o.imbue(std::locale::classic());
        o.setf(std::ios::fixed, std::ios::floatfield);
        o.precision(1);
        o << v;
        return o.str();
    }

    /** Reads a number out of whatever the user typed or pasted.

        A plain EDIT control carries no locale of its own, so both the full stop
        and the comma are accepted as the decimal separator; a degree sign, in
        either the ASCII or the UTF-8 spelling, and surrounding spaces are
        ignored. Parsing happens in the C locale explicitly rather than in
        whichever one the host has installed, so the same keystrokes mean the
        same angle on every machine. */
    bool ParseAngle(const char* text, double* value)
    {
        if (text == nullptr) return false;

        std::string cleaned;
        for (const char* p = text; *p != 0; ++p)
        {
            const unsigned char c = static_cast<unsigned char>(*p);
            if (c == ',') { cleaned.push_back('.'); continue; }
            if (c == ' ' || c == '\t') continue;
            if (c == 0xB0 || c == 0xC2) continue;        // degree sign, UTF-8 or Latin-1
            cleaned.push_back(static_cast<char>(c));
        }
        if (cleaned.empty()) return false;

        _locale_t invariant = _create_locale(LC_NUMERIC, "C");
        if (invariant == nullptr) return false;
        char* end = nullptr;
        const double parsed = _strtod_l(cleaned.c_str(), &end, invariant);
        _free_locale(invariant);

        if (end == cleaned.c_str()) return false;
        if (!(parsed == parsed)) return false;                   // NaN
        if (parsed > 1.0e12 || parsed < -1.0e12) return false;   // infinity, or nonsense
        *value = parsed;
        return true;
    }

    void SetEditValue(HWND edit, double v)
    {
        SetWindowTextA(edit, Format(v).c_str());
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
            const int pos = static_cast<int>(SendMessage(dd->shearSlider, TBM_GETPOS, 0, 0));
            dd->state->shearAngle = static_cast<double>(pos) / kScale;
            SetEditValue(dd->shearEdit, dd->state->shearAngle);
        }
        else
        {
            const int pos = static_cast<int>(SendMessage(dd->axisSlider, TBM_GETPOS, 0, 0));
            dd->state->axisAngle = static_cast<double>(pos) / kScale;
            SetEditValue(dd->axisEdit, dd->state->axisAngle);
        }
        dd->updating = false;
        Republish(dd);
    }

    void ApplyValue(DialogData* dd, bool isShear, double v)
    {
        dd->updating = true;
        if (isShear)
        {
            v = Clamp(v, kShearMin, kShearMax);
            dd->state->shearAngle = v;
            SendMessage(dd->shearSlider, TBM_SETPOS, TRUE,
                        static_cast<LPARAM>(std::lround(v * kScale)));
            SetEditValue(dd->shearEdit, v);
        }
        else
        {
            // An axis angle outside the slider's range is still a valid angle,
            // so it is wrapped into the range rather than clipped to its end:
            // 200 degrees means the same shear as -160 and should show as -160,
            // where clamping to 180 would silently change the result.
            v = shear::SanitizeAxisAngle(v);
            dd->state->axisAngle = v;
            SendMessage(dd->axisSlider, TBM_SETPOS, TRUE,
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
        char buf[64] = { 0 };
        GetWindowTextA(field, buf, sizeof(buf) - 1);

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
            SendMessage(hwnd, EM_SETSEL, 0, -1);
            return 0;
        }
        if (msg == WM_NCDESTROY) RemoveWindowSubclass(hwnd, EditSubclassProc, id);
        return DefSubclassProc(hwnd, msg, wp, lp);
    }

    HWND MakeLabel(HWND parent, HINSTANCE inst, const char* text, int x, int y, int w, int h)
    {
        return CreateWindowExA(0, "STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT,
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

        font.lfHeight = -MulDiv(9, dpi, 72);
        font.lfWidth = 0;
        return CreateFontIndirectW(&font);
    }

    LRESULT CALLBACK DialogProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
    {
        DialogData* dd = reinterpret_cast<DialogData*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

        switch (msg)
        {
            case WM_CREATE:
            {
                CREATESTRUCT* cs = reinterpret_cast<CREATESTRUCT*>(lp);
                dd = static_cast<DialogData*>(cs->lpCreateParams);
                SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(dd));
                const HINSTANCE inst = cs->hInstance;

                dd->dpi = DpiOf(hwnd);
                const int dpi = dd->dpi;
                #define S(v) MulDiv((v), dpi, 96)

                MakeLabel(hwnd, inst, "Shear Angle", S(16), S(18), S(90), S(18));
                dd->shearSlider = CreateWindowExA(0, TRACKBAR_CLASSA, "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    S(110), S(14), S(220), S(26), hwnd,
                    ControlId(kIdShearSlider), inst, nullptr);
                SendMessage(dd->shearSlider, TBM_SETRANGE, TRUE,
                            MAKELPARAM(static_cast<int>(kShearMin * kScale),
                                       static_cast<int>(kShearMax * kScale)));
                SendMessage(dd->shearSlider, TBM_SETPOS, TRUE,
                            static_cast<LPARAM>(std::lround(dd->state->shearAngle * kScale)));
                dd->shearEdit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    S(340), S(16), S(60), S(22), hwnd,
                    ControlId(kIdShearEdit), inst, nullptr);
                SetEditValue(dd->shearEdit, dd->state->shearAngle);
                MakeLabel(hwnd, inst, "\xc2\xb0", S(404), S(18), S(14), S(18));

                MakeLabel(hwnd, inst, "Axis Angle", S(16), S(54), S(90), S(18));
                dd->axisSlider = CreateWindowExA(0, TRACKBAR_CLASSA, "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    S(110), S(50), S(220), S(26), hwnd,
                    ControlId(kIdAxisSlider), inst, nullptr);
                SendMessage(dd->axisSlider, TBM_SETRANGE, TRUE,
                            MAKELPARAM(static_cast<int>(kAxisMin * kScale),
                                       static_cast<int>(kAxisMax * kScale)));
                SendMessage(dd->axisSlider, TBM_SETPOS, TRUE,
                            static_cast<LPARAM>(std::lround(dd->state->axisAngle * kScale)));
                dd->axisEdit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    S(340), S(52), S(60), S(22), hwnd,
                    ControlId(kIdAxisEdit), inst, nullptr);
                SetEditValue(dd->axisEdit, dd->state->axisAngle);
                MakeLabel(hwnd, inst, "\xc2\xb0", S(404), S(54), S(14), S(18));

                dd->preview = CreateWindowExA(0, "BUTTON", "Preview",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX,
                    S(16), S(92), S(90), S(22), hwnd,
                    ControlId(kIdPreview), inst, nullptr);
                SendMessage(dd->preview, BM_SETCHECK,
                            dd->state->previewEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
                EnableWindow(dd->preview, dd->state->allowPreview ? TRUE : FALSE);

                CreateWindowExA(0, "BUTTON", "Reset",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    S(120), S(92), S(70), S(24), hwnd,
                    ControlId(kIdReset), inst, nullptr);
                CreateWindowExA(0, "BUTTON", "Cancel",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    S(250), S(92), S(78), S(24), hwnd,
                    ControlId(IDCANCEL), inst, nullptr);
                CreateWindowExA(0, "BUTTON", "OK",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
                    S(338), S(92), S(78), S(24), hwnd,
                    ControlId(IDOK), inst, nullptr);
                #undef S

                // Give every control the standard UI font instead of the
                // 1980s system font CreateWindow hands out by default.
                dd->font = MakeUiFont(dd->dpi);
                if (dd->font != nullptr)
                {
                    EnumChildWindows(hwnd, [](HWND child, LPARAM font) -> BOOL {
                        SendMessage(child, WM_SETFONT, static_cast<WPARAM>(font), TRUE);
                        return TRUE;
                    }, reinterpret_cast<LPARAM>(dd->font));
                }

                SetWindowSubclass(dd->shearEdit, EditSubclassProc, kIdShearEdit,
                                  reinterpret_cast<DWORD_PTR>(dd));
                SetWindowSubclass(dd->axisEdit, EditSubclassProc, kIdAxisEdit,
                                  reinterpret_cast<DWORD_PTR>(dd));

                Republish(dd);
                return 0;
            }

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
                        dd->state->previewEnabled =
                            SendMessage(dd->preview, BM_GETCHECK, 0, 0) == BST_CHECKED;
                        Republish(dd);
                        return 0;
                    case kIdReset:
                        dd->updating = true;
                        dd->state->shearAngle = 0.0;
                        dd->state->axisAngle = 0.0;
                        SendMessage(dd->shearSlider, TBM_SETPOS, TRUE, 0);
                        SendMessage(dd->axisSlider, TBM_SETPOS, TRUE, 0);
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
                PostMessage(nullptr, WM_NULL, 0, 0);
                return 0;

            default:
                break;
        }
        return DefWindowProc(hwnd, msg, wp, lp);
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
        WNDCLASSEXA wc;
        ZeroMemory(&wc, sizeof(wc));
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = DialogProc;
        wc.hInstance = inst;
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
        wc.lpszClassName = kClassName;
        if (!RegisterClassExA(&wc))
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

    RECT rc = { 0, 0, MulDiv(432, DpiOf(parent), 96), MulDiv(160, DpiOf(parent), 96) };
    AdjustWindowRectEx(&rc, WS_CAPTION | WS_SYSMENU, FALSE, WS_EX_DLGMODALFRAME);

    const HWND hwnd = CreateWindowExA(
        WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT,
        kClassName, "Shear",
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
        if (!GetMessage(&msg, nullptr, 0, 0))
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
        if (nudge || !IsDialogMessage(hwnd, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    if (dd.font != nullptr) { DeleteObject(dd.font); dd.font = nullptr; }

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
    UnregisterClassA(kClassName, gClassInstance);
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
