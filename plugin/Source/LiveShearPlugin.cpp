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

//  LiveShearPlugin.cpp -- see LiveShearPlugin.h.

#include "IllustratorSDK.h"
#include "LiveShearPlugin.h"
#include "LiveShearSuites.h"
#include "ShearMath.h"
#include "ShearDialogModel.h"
#include "Introspect.h"
#include "ShearLog.h"
#include "ShearDialog.h"
#include "ShearAbout.h"
#include "ShearTheme.h"
#include "SDKDef.h"
#include "SDKAboutPluginsHelper.h"

#include <sstream>
#include <iomanip>
#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <locale>

namespace
{
    /** Splits `text` on `sep` into at most `maxFields` pieces; the last piece
        keeps any remaining separators. */
    std::vector<std::string> Split(const std::string& text, char sep, size_t maxFields = 0)
    {
        std::vector<std::string> out;
        size_t pos = 0;
        while (pos <= text.size())
        {
            if (maxFields && out.size() + 1 == maxFields)
            {
                out.push_back(text.substr(pos));
                return out;
            }
            const size_t next = text.find(sep, pos);
            if (next == std::string::npos)
            {
                out.push_back(text.substr(pos));
                return out;
            }
            out.push_back(text.substr(pos, next - pos));
            pos = next + 1;
        }
        return out;
    }

    double Field(const std::vector<std::string>& f, size_t i, double dflt = 0.0)
    {
        return i < f.size() && !f[i].empty() ? std::atof(f[i].c_str()) : dflt;
    }

    /** A number read in the C locale, whatever locale the host has set, so a
        value a probe saved as 12.5 comes back as 12.5 and not as 12. */
    double InvariantNumber(const std::string& text, double dflt = 0.0)
    {
        std::istringstream in(text);
        in.imbue(std::locale::classic());
        double value = dflt;
        in >> value;
        return in.fail() ? dflt : value;
    }

    bool BoolField(const std::vector<std::string>& f, size_t i, bool dflt)
    {
        if (i >= f.size() || f[i].empty()) return dflt;
        return f[i] == "1" || f[i] == "true";
    }
}

Plugin* AllocatePlugin(SPPluginRef pluginRef)
{
    return new LiveShearPlugin(pluginRef);
}

void FixupReload(Plugin* plugin)
{
    LiveShearPlugin::FixupVTable(static_cast<LiveShearPlugin*>(plugin));
}

LiveShearPlugin::LiveShearPlugin(SPPluginRef pluginRef)
    : Plugin(pluginRef),
      fAboutPluginMenu(nullptr),
      fEffectMenu(nullptr),
      fShearEffect(nullptr)
{
    strncpy(fPluginName, kLiveShearPluginName, kMaxStringLength);
}

ASErr LiveShearPlugin::Message(char* caller, char* selector, void* message)
{
    ASErr error = kNoErr;

    try
    {
        if (std::strcmp(caller, kCallerAIScriptMessage) == 0)
            return HandleScriptMessage(selector, static_cast<AIScriptMessage*>(message));

        error = Plugin::Message(caller, selector, message);
    }
    catch (ai::Error& ex)
    {
        error = ex;
    }
    catch (...)
    {
        error = kCantHappenErr;
    }

    if (error)
    {
        if (error == kUnhandledMsgErr)
            error = kNoErr;
        else
            Plugin::ReportError(error, caller, selector, message);
    }
    return error;
}

ASErr LiveShearPlugin::StartupPlugin(SPInterfaceMessage* message)
{
    ASErr error = Plugin::StartupPlugin(message);
    if (error) return error;
    error = this->AddMenus(message);
    if (error) return error;
    return this->AddLiveEffects(message);
}

ASErr LiveShearPlugin::ShutdownPlugin(SPInterfaceMessage* message)
{
    // The dialog registers a window class lazily and keeps it for the life of
    // the session. If this module were unloaded with the class still
    // registered, its window procedure would point into freed memory, so it
    // goes now.
    ShutdownShearDialog();
    message->d.globals = nullptr;
    return Plugin::ShutdownPlugin(message);
}

ASErr LiveShearPlugin::AddMenus(SPInterfaceMessage* message)
{
    // Our own group, not the SDK's. Its defaults file the plugin under "About
    // SDK Plug-ins" and describe it as an Adobe sample, which would be a false
    // claim on a third-party binary.
    SDKAboutPluginsHelper aboutPluginsHelper;
    return aboutPluginsHelper.AddAboutPluginsMenuItem(
        message,
        kShearAboutGroupName,
        ai::UnicodeString(kShearAboutGroupTitle),
        kShearAboutMenuTitle,
        &this->fAboutPluginMenu);
}

ASErr LiveShearPlugin::AddLiveEffects(SPInterfaceMessage* message)
{
    char nameStr[]      = kShearEffectName;
    char titleStr[]     = kShearEffectTitle;
    char menuTitleStr[] = kShearEffectMenuTitle;

    AILiveEffectData effectData;
    effectData.self = message->d.self;
    effectData.name = nameStr;
    effectData.title = titleStr;
    effectData.majorVersion = 1;
    effectData.minorVersion = 0;
    // Shear is a pure affine transform, so it can take whatever art the
    // appearance pipeline hands it -- except plugin groups, which we let
    // Illustrator resolve to their result art first.
    effectData.prefersAsInput = kAnyInputArtButPluginArt;
    // Post-effect: it transforms the painted result, which is what makes
    // "Stroke then Shear" differ from "Shear then Stroke" in the usual way.
    effectData.styleFilterFlags = kPostEffectFilter;

    ASErr error = sAILiveEffect->AddLiveEffect(&effectData, &this->fShearEffect);
    if (error) return error;

    AddLiveEffectMenuData menuData;
    /* No submenu: the item sits on the Effect menu itself, among the
       third-party effects, and Illustrator puts it in its "Effects 3rd Party"
       group.

       A category here would not do what it looks like it does. Illustrator
       files a third-party category in a menu group it names "Live 3rd Party "
       plus the category, always -- so "Distort & Transform" did not join
       Adobe's submenu of that name, it made a second one beside it, and since
       the group name is also the submenu's label, the bare ampersand was eaten
       as a Windows mnemonic and it read "Distort  Transform".

       Adobe's own submenu can in fact be reached, by creating that third-party
       group next to it before the host does. It was tried, and it costs: an
       item there stops responding to Effect > Apply Last Effect, silently.
       See LIVE_SHEAR_INVESTIGATION.md. */
    menuData.category = nullptr;
    menuData.title = menuTitleStr;
    menuData.options = 0;

    error = sAILiveEffect->AddLiveEffectMenuItem(this->fShearEffect, nameStr,
                                                 &menuData, &this->fEffectMenu, nullptr);
    if (error) return error;

    return sAIMenu->UpdateMenuItemAutomatically(this->fEffectMenu, kAutoEnableMenuItemAction,
                                                0, 0, kIfAnyArt, 0, 0, 0);
}

ASErr LiveShearPlugin::GoLiveEffect(AILiveEffectGoMessage* message)
{
    if (message->effect != this->fShearEffect) return kNoErr;
    return fShear.Go(message);
}

ASErr LiveShearPlugin::EditLiveEffectParameters(AILiveEffectEditParamMessage* message)
{
    if (message->effect != this->fShearEffect) return kNoErr;
    return fShear.EditParameters(message);
}

ASErr LiveShearPlugin::LiveEffectInterpolate(AILiveEffectInterpParamMessage* message)
{
    if (message->effect != this->fShearEffect) return kNoErr;
    return fShear.Interpolate(message);
}

#ifdef WIN_ENV
/* Illustrator's own dialog colors, turned into the plain struct the About
   dialog takes. This is the seam: the host is asked here, so ShearAbout.cpp
   still compiles without a line of Illustrator in it.

   ShearTheme already reads the suite for the Shear dialog, so the numbers come
   from one place and the two windows cannot end up different shades of the
   same theme. */
static ShearAboutTheme AboutThemeFromHost()
{
    const sheartheme::Theme host = sheartheme::Read();

    ShearAboutTheme about;
    if (!host.fromHost) return about;   /* system colors, as the default already is */

    about.panel        = host.editBackground;
    about.panelText    = host.editText;
    about.band         = host.background;
    about.bandText     = host.text;
    about.rule         = host.border;
    about.link         = host.focusRing;

    /* The host answered, so the window is ours to draw entirely: a stock OK
       button and a white caption would be the two pieces left in system
       colors. */
    about.ownerDrawButton = true;
    about.button          = host.control;
    about.buttonText      = host.text;
    about.buttonBorder    = host.border;
    about.darkTitleBar    = host.dark;
    return about;
}
#endif

ASErr LiveShearPlugin::GoMenuItem(AIMenuMessage* message)
{
    if (message->menuItem == this->fAboutPluginMenu)
    {
#ifdef WIN_ENV
        /* Our own module, not the host's: the dialog resource lives in the
           .aip. Taken from the address of a function in this module rather
           than cached from DllMain, which the SDK's entry point does not hand
           us. */
        HMODULE self = nullptr;
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               reinterpret_cast<LPCWSTR>(&ShearShowAboutDialog),
                               &self) && self != nullptr)
        {
            if (ShearShowAboutDialog(self, GetActiveWindow(), AboutThemeFromHost()))
                return kNoErr;
        }
#endif

        /* Last resort: a plain alert, same words. Reached only if the dialog
           could not be created -- an old common-controls library, or a
           resource that failed to load. */
        SDKAboutPluginsHelper aboutPluginsHelper;
        const std::string about =
            std::string(kShearProductName) + " " + kShearVersionString + "\n" +
            kShearDescription + "\n" + kShearHomePage + "\n" + kShearCopyright;
        aboutPluginsHelper.PopAboutBox(message, "About Shear", about.c_str());
    }
    return kNoErr;
}

//  The research bridge. ExtendScript reaches every probe below through
//      app.sendScriptMessage("LiveShear", "<selector>", "<arguments>")
//  which means the whole experiment matrix can be driven from a script
//  instead of by hand.
ASErr LiveShearPlugin::HandleScriptMessage(const char* selector, AIScriptMessage* message)
{
    if (message == nullptr) return kNoErr;

    const std::string sel(selector ? selector : "");
    const std::string in = message->inParam.as_UTF8();
    std::string result;

    if (sel == "version")
    {
        std::ostringstream o;
        o << kShearProductName << " " << kShearVersionString << "\n"
          << "plugin: " << kLiveShearPluginName << "\n"
          << "effect name: " << kShearEffectName << "\n"
          << "parameter schema: " << kShearSchema << "\n";
        result = o.str();
    }
    else if (sel == "log")
    {
        result = shearlog::Read();
    }
    else if (sel == "menu groups")
    {
        /* Every menu group Illustrator holds, by name. The About group is
           shared between this plugin and the others from the same publisher,
           and "shared" is only observable from here: the menu bar cannot be
           read from scripting, and Illustrator's own shell does not answer the
           Alt key the way a stock menu bar would, so a screen capture is not
           available either. */
        std::ostringstream o;
        ai::int32 count = 0;
        if (!sAIMenu->CountMenuGroups(&count))
        {
            for (ai::int32 i = 0; i < count; ++i)
            {
                AIMenuGroup group = nullptr;
                if (sAIMenu->GetNthMenuGroup(i, &group) || group == nullptr) continue;
                const char* name = nullptr;
                if (sAIMenu->GetMenuGroupName(group, &name) || name == nullptr) continue;
                o << name << "\n";
            }
        }
        result = o.str();
    }
    else if (sel == "effect menu")
    {
        /* Where Illustrator actually filed the effect's menu item, and what it
           can be reached by. The placement is not observable any other way:
           the menu bar is not scriptable, and this host's shell does not
           answer the Alt key the way a stock menu bar would, so there is no
           screen capture to fall back on either.

           The group name matters because a category would change it. An item
           in "Effects 3rd Party" is on the Effect menu itself; anything called
           "Live 3rd Party ..." is in a submenu of its own; anything called
           "Live Vector ..." is inside one of Adobe's, which is the placement
           that silently breaks Apply Last Effect. */
        std::ostringstream o;
        AIMenuGroup group = nullptr;
        const char* name = nullptr;
        if (!sAIMenu->GetItemMenuGroup(this->fEffectMenu, &group) && group != nullptr &&
            !sAIMenu->GetMenuGroupName(group, &name) && name != nullptr)
            o << "group\t" << name << "\n";
        else
            o << "group\t(could not be read)\n";

        ai::UnicodeString text;
        if (!sAIMenu->GetItemText(this->fEffectMenu, text))
            o << "item text\t" << text.as_UTF8() << "\n";

        const char* key = nullptr;
        if (!sAIMenu->GetMenuItemKeyboardShortcutDictionaryKey(this->fEffectMenu, &key) &&
            key != nullptr)
            o << "command string\t" << key << "\n";

        result = o.str();
    }
    else if (sel == "about")
    {
        /* Opens the About dialog, so a probe can photograph it. The menu item
           that normally opens it is added without a name, so there is no
           command string for executeMenuCommand to reach it by. */
#ifdef WIN_ENV
        HMODULE self = nullptr;
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               reinterpret_cast<LPCWSTR>(&ShearShowAboutDialog),
                               &self) && self != nullptr)
        {
            result = ShearShowAboutDialog(self, GetActiveWindow(), AboutThemeFromHost())
                         ? "shown" : "the dialog could not be created";
        }
        else result = "could not find this plugin's own module";
#else
        result = "Windows only";
#endif
    }
    else if (sel == "registry")
    {
        result = introspect::DumpLiveEffectRegistry();
    }
    else if (sel == "appearance")
    {
        result = introspect::DumpSelectionAppearance();
    }
    else if (sel == "selection")
    {
        result = introspect::DumpSelectionSpecs();
    }
    else if (sel == "geometry")
    {
        result = introspect::DumpSelectionGeometry();
    }
    else if (sel == "native shear")
    {
        // shear,axis,dx,dy,copy,objects,patterns
        const std::vector<std::string> f = Split(in, ',');
        result = introspect::PlayNativeShear(Field(f, 0), Field(f, 1), Field(f, 2), Field(f, 3),
                                             BoolField(f, 4, false), BoolField(f, 5, true),
                                             BoolField(f, 6, false));
    }
    else if (sel == "apply effect")
    {
        // effectName|paramSpec
        const std::vector<std::string> f = Split(in, '|', 2);
        result = introspect::ApplyEffectByName(f.size() > 0 ? f[0] : std::string(),
                                               f.size() > 1 ? f[1] : std::string());
    }
    else if (sel == "bounds")
    {
        result = introspect::DumpSelectionBounds();
    }
    else if (sel == "bounds flags")
    {
        result = introspect::DumpBoundsFlags();
    }
    else if (sel == "move effect")
    {
        const std::vector<std::string> f = Split(in, ',');
        result = introspect::MoveEffect(static_cast<ai::int32>(Field(f, 0)),
                                        static_cast<ai::int32>(Field(f, 1)));
    }
    else if (sel == "remove effect")
    {
        result = introspect::RemoveEffect(std::atoi(in.c_str()));
    }
    else if (sel == "count effects")
    {
        result = introspect::CountEffects();
    }
    else if (sel == "edit effect")
    {
        result = introspect::EditEffect(std::atoi(in.c_str()));
    }
    else if (sel == "dialog memory")
    {
        /* What the dialog opens a new effect with, and the means to change it.
           The dialog probes change it just by using the dialog, and a person's
           own Illustrator session should get back what it had, so a probe reads
           this first and puts it back afterwards.

               (empty)             reads
               forget              forgets the remembered angles
               angles <s>|<a>      remembers these angles
               preview 0|1         sets the Preview preference

           Every form answers with the state it leaves. */
        std::ostringstream o;
        o.imbue(std::locale::classic());
        if (in == "forget")
        {
            fShear.SetLastUsed(shear::LastUsed());
        }
        else if (in.compare(0, 7, "angles ") == 0)
        {
            const std::vector<std::string> f = Split(in.substr(7), '|');
            shear::LastUsed last;
            last.known = true;
            last.shearAngle = shear::SanitizeShearAngle(InvariantNumber(f.size() > 0 ? f[0] : std::string()));
            last.axisAngle = shear::SanitizeAxisAngle(InvariantNumber(f.size() > 1 ? f[1] : std::string()));
            fShear.SetLastUsed(last);
        }
        else if (in.compare(0, 8, "preview ") == 0)
        {
            ShearEffect::WritePreviewPreference(in.substr(8) != "0");
        }
        else if (!in.empty())
        {
            o << "Expected nothing, forget, angles <shear>|<axis>, or preview 0|1\n";
        }
        const shear::LastUsed& last = fShear.GetLastUsed();
        o << "remembered\t" << (last.known ? 1 : 0) << "\n"
          << "shear\t" << last.shearAngle << "\n"
          << "axis\t" << last.axisAngle << "\n"
          << "preview\t" << (ShearEffect::ReadPreviewPreference() ? 1 : 0) << "\n";
        result = o.str();
    }
    else if (sel == "set param")
    {
        // index|key|type|value
        const std::vector<std::string> f = Split(in, '|', 4);
        if (f.size() < 4)
            result = "Expected index|key|type|value\n";
        else
            result = introspect::SetEffectParameter(std::atoi(f[0].c_str()), f[1], f[2], f[3]);
    }
    else if (sel == "delete param")
    {
        const std::vector<std::string> f = Split(in, '|', 2);
        if (f.size() < 2)
            result = "Expected index|key\n";
        else
            result = introspect::DeleteEffectParameter(std::atoi(f[0].c_str()), f[1]);
    }
    else if (sel == "matrix")
    {
        // shear,axis,anchorX,anchorY -- our own idea of the transform, so it
        // can be checked against what the host actually did.
        const std::vector<std::string> f = Split(in, ',');
        AIRealPoint anchor;
        anchor.h = static_cast<AIReal>(Field(f, 2));
        anchor.v = static_cast<AIReal>(Field(f, 3));
        const AIRealMatrix m = shear::MatrixAbout(Field(f, 0), Field(f, 1), anchor);
        std::ostringstream o;
        o << std::fixed << std::setprecision(9)
          << m.a << "," << m.b << "," << m.c << "," << m.d << "," << m.tx << "," << m.ty << "\n";
        result = o.str();
    }
    else
    {
        result = "Unknown selector \"" + sel + "\".\n";
    }

    message->outParam = ai::UnicodeString::FromUTF8(result.c_str());
    return kNoErr;
}

// End LiveShearPlugin.cpp
