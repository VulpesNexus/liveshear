//  ShearDialog.cpp -- a plain Win32 modal dialog, built at run time so the
//  plug-in carries no dialog resource template.
//
//  Two rows, each a slider paired with an editable numeric field, plus a
//  Preview check box. Moving a slider writes the new values into the effect's
//  parameter dictionary and asks Illustrator to re-run the effect, so the
//  artwork updates under the dialog. Cancel puts the dictionary back the way it
//  was and re-runs once more, so nothing is left behind.

#include "IllustratorSDK.h"
#include "ShearDialog.h"
#include "ShearEffect.h"
#include "LiveShearSuites.h"
#include "LiveShearID.h"
#include "ShearLog.h"

#ifdef WIN_ENV

#include <windows.h>
#include <commctrl.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <sstream>

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

    const double kShearMin = -89.0;
    const double kShearMax =  89.0;
    const double kAxisMin  = -180.0;
    const double kAxisMax  =  180.0;

    struct DialogData
    {
        ShearDialogState* state = nullptr;
        double entryShear = 0.0;
        double entryAxis = 0.0;
        bool committed = false;
        bool updating = false;
        HWND shearSlider = nullptr;
        HWND shearEdit = nullptr;
        HWND axisSlider = nullptr;
        HWND axisEdit = nullptr;
        HWND preview = nullptr;
    };

    double Clamp(double v, double lo, double hi)
    {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    std::string Format(double v)
    {
        char buf[32];
        std::snprintf(buf, sizeof(buf), "%.1f", v);
        return buf;
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
        sAIDictionary->SetRealEntry(st->parameters, sAIDictionary->Key(kShearAngleKey),
                                    static_cast<AIReal>(shearAngle));
        sAIDictionary->SetRealEntry(st->parameters, sAIDictionary->Key(kShearAxisKey),
                                    static_cast<AIReal>(axisAngle));
        ShearEffect::UpdateDisplayString(st->parameters,
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

    void SyncFromEdit(DialogData* dd, bool isShear)
    {
        if (dd->updating) return;
        const HWND field = isShear ? dd->shearEdit : dd->axisEdit;
        char buf[64] = { 0 };
        const int got = GetWindowTextA(field, buf, sizeof(buf) - 1);
        if (shearlog::Enabled())
        {
            std::ostringstream o;
            o << "dialog: SyncFromEdit " << (isShear ? "shear" : "axis")
              << " hwnd=" << (field ? 1 : 0) << " chars=" << got << " text='" << buf << "'";
            shearlog::Write(o.str());
        }
        if (buf[0] == 0) return;
        double v = std::atof(buf);
        dd->updating = true;
        if (isShear)
        {
            v = Clamp(v, kShearMin, kShearMax);
            dd->state->shearAngle = v;
            SendMessage(dd->shearSlider, TBM_SETPOS, TRUE, static_cast<LPARAM>(std::lround(v * kScale)));
        }
        else
        {
            v = Clamp(v, kAxisMin, kAxisMax);
            dd->state->axisAngle = v;
            SendMessage(dd->axisSlider, TBM_SETPOS, TRUE, static_cast<LPARAM>(std::lround(v * kScale)));
        }
        dd->updating = false;
        Republish(dd);
    }

    HWND MakeLabel(HWND parent, HINSTANCE inst, const char* text, int x, int y, int w, int h)
    {
        return CreateWindowExA(0, "STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT,
                               x, y, w, h, parent, nullptr, inst, nullptr);
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

                MakeLabel(hwnd, inst, "Shear Angle", 16, 18, 90, 18);
                dd->shearSlider = CreateWindowExA(0, TRACKBAR_CLASSA, "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    110, 14, 220, 26, hwnd, reinterpret_cast<HMENU>(kIdShearSlider), inst, nullptr);
                SendMessage(dd->shearSlider, TBM_SETRANGE, TRUE,
                            MAKELPARAM(static_cast<int>(kShearMin * kScale), static_cast<int>(kShearMax * kScale)));
                SendMessage(dd->shearSlider, TBM_SETPOS, TRUE,
                            static_cast<LPARAM>(std::lround(dd->state->shearAngle * kScale)));
                dd->shearEdit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    340, 16, 60, 22, hwnd, reinterpret_cast<HMENU>(kIdShearEdit), inst, nullptr);
                SetEditValue(dd->shearEdit, dd->state->shearAngle);
                MakeLabel(hwnd, inst, "\xc2\xb0", 404, 18, 14, 18);

                MakeLabel(hwnd, inst, "Axis Angle", 16, 54, 90, 18);
                dd->axisSlider = CreateWindowExA(0, TRACKBAR_CLASSA, "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                    110, 50, 220, 26, hwnd, reinterpret_cast<HMENU>(kIdAxisSlider), inst, nullptr);
                SendMessage(dd->axisSlider, TBM_SETRANGE, TRUE,
                            MAKELPARAM(static_cast<int>(kAxisMin * kScale), static_cast<int>(kAxisMax * kScale)));
                SendMessage(dd->axisSlider, TBM_SETPOS, TRUE,
                            static_cast<LPARAM>(std::lround(dd->state->axisAngle * kScale)));
                dd->axisEdit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_RIGHT | ES_AUTOHSCROLL,
                    340, 52, 60, 22, hwnd, reinterpret_cast<HMENU>(kIdAxisEdit), inst, nullptr);
                SetEditValue(dd->axisEdit, dd->state->axisAngle);
                MakeLabel(hwnd, inst, "\xc2\xb0", 404, 54, 14, 18);

                dd->preview = CreateWindowExA(0, "BUTTON", "Preview",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX,
                    16, 92, 90, 22, hwnd, reinterpret_cast<HMENU>(kIdPreview), inst, nullptr);
                SendMessage(dd->preview, BM_SETCHECK,
                            dd->state->previewEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
                EnableWindow(dd->preview, dd->state->allowPreview ? TRUE : FALSE);

                CreateWindowExA(0, "BUTTON", "Reset",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    120, 92, 70, 24, hwnd, reinterpret_cast<HMENU>(kIdReset), inst, nullptr);
                CreateWindowExA(0, "BUTTON", "Cancel",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    250, 92, 78, 24, hwnd, reinterpret_cast<HMENU>(IDCANCEL), inst, nullptr);
                CreateWindowExA(0, "BUTTON", "OK",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
                    338, 92, 78, 24, hwnd, reinterpret_cast<HMENU>(IDOK), inst, nullptr);

                // Give every control the standard UI font instead of the
                // 1980s system font CreateWindow hands out by default.
                const HFONT font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
                EnumChildWindows(hwnd, [](HWND child, LPARAM font) -> BOOL {
                    SendMessage(child, WM_SETFONT, static_cast<WPARAM>(font), TRUE);
                    return TRUE;
                }, reinterpret_cast<LPARAM>(font));

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
                if (dd) dd->committed = false;
                DestroyWindow(hwnd);
                return 0;

            case WM_DESTROY:
                PostQuitMessage(0);
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

    static const char* kClassName = "VulpesNexusShearDialog";
    static bool registered = false;
    if (!registered)
    {
        WNDCLASSEXA wc = { 0 };
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
        registered = true;
    }

    HWND parent = nullptr;
    AIWindowRef appWindow = nullptr;
    if (!sAIAppContext->GetPlatformAppWindow(&appWindow))
        parent = reinterpret_cast<HWND>(appWindow);

    DialogData dd;
    dd.state = &state;
    dd.entryShear = state.shearAngle;
    dd.entryAxis = state.axisAngle;

    RECT rc = { 0, 0, 432, 160 };
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

    MSG msg;
    while (GetMessage(&msg, nullptr, 0, 0) > 0)
    {
        if (!IsDialogMessage(hwnd, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    if (parent)
    {
        EnableWindow(parent, TRUE);
        SetForegroundWindow(parent);
    }

    {
        std::ostringstream o;
        o << "dialog: closed, committed=" << (dd.committed ? 1 : 0)
          << " shear=" << state.shearAngle << " axis=" << state.axisAngle;
        shearlog::Write(o.str());
    }

    if (!dd.committed)
    {
        state.shearAngle = dd.entryShear;
        state.axisAngle = dd.entryAxis;
        if (state.allowPreview && state.parameters && state.context)
        {
            sAIDictionary->SetRealEntry(state.parameters, sAIDictionary->Key(kShearAngleKey),
                                        static_cast<AIReal>(state.shearAngle));
            sAIDictionary->SetRealEntry(state.parameters, sAIDictionary->Key(kShearAxisKey),
                                        static_cast<AIReal>(state.axisAngle));
            ShearEffect::UpdateDisplayString(state.parameters,
                                             static_cast<AIReal>(state.shearAngle),
                                             static_cast<AIReal>(state.axisAngle));
            sAILiveEffect->UpdateParameters(state.context);
        }
    }
    return dd.committed;
}

#else  // !WIN_ENV

bool RunShearDialog(ShearDialogState&)
{
    return false;
}

#endif
