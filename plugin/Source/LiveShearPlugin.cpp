//  LiveShearPlugin.cpp -- see LiveShearPlugin.h.

#include "IllustratorSDK.h"
#include "LiveShearPlugin.h"
#include "LiveShearSuites.h"
#include "ShearMath.h"
#include "Introspect.h"
#include "ShearLog.h"
#include "SDKDef.h"
#include "SDKAboutPluginsHelper.h"

#include <sstream>
#include <iomanip>
#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>

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
    message->d.globals = nullptr;
    return Plugin::ShutdownPlugin(message);
}

ASErr LiveShearPlugin::AddMenus(SPInterfaceMessage* message)
{
    SDKAboutPluginsHelper aboutPluginsHelper;
    return aboutPluginsHelper.AddAboutPluginsMenuItem(
        message,
        kSDKDefAboutSDKCompanyPluginsGroupName,
        ai::UnicodeString(kSDKDefAboutSDKCompanyPluginsGroupNameString),
        "Live Shear...",
        &this->fAboutPluginMenu);
}

ASErr LiveShearPlugin::AddLiveEffects(SPInterfaceMessage* message)
{
    char nameStr[]      = kShearEffectName;
    char titleStr[]     = kShearEffectTitle;
    char menuTitleStr[] = kShearEffectMenuTitle;
    char categoryStr[]  = kShearEffectCategory;

    AILiveEffectData effectData;
    effectData.self = message->d.self;
    effectData.name = nameStr;
    effectData.title = titleStr;
    effectData.majorVersion = 1;
    effectData.minorVersion = 0;
    // Shear is a pure affine transform, so it can take whatever art the
    // appearance pipeline hands it -- except plug-in groups, which we let
    // Illustrator resolve to their result art first.
    effectData.prefersAsInput = kAnyInputArtButPluginArt;
    // Post-effect: it transforms the painted result, which is what makes
    // "Stroke then Shear" differ from "Shear then Stroke" in the usual way.
    effectData.styleFilterFlags = kPostEffectFilter;

    ASErr error = sAILiveEffect->AddLiveEffect(&effectData, &this->fShearEffect);
    if (error) return error;

    AddLiveEffectMenuData menuData;
    menuData.category = categoryStr;
    menuData.title = menuTitleStr;
    menuData.options = 0;

    AIMenuItemHandle menuHandle = nullptr;
    error = sAILiveEffect->AddLiveEffectMenuItem(this->fShearEffect, nameStr,
                                                 &menuData, &menuHandle, nullptr);
    if (error) return error;

    return sAIMenu->UpdateMenuItemAutomatically(menuHandle, kAutoEnableMenuItemAction,
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

ASErr LiveShearPlugin::GoMenuItem(AIMenuMessage* message)
{
    if (message->menuItem == this->fAboutPluginMenu)
    {
        SDKAboutPluginsHelper aboutPluginsHelper;
        aboutPluginsHelper.PopAboutBox(message, "About Live Shear",
                                       kSDKDefAboutSDKCompanyPluginsAlertString);
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
        o << kLiveShearPluginName << " 0.1\n"
          << "effect name: " << kShearEffectName << "\n";
        result = o.str();
    }
    else if (sel == "log")
    {
        result = shearlog::Read();
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
    else if (sel == "edit effect")
    {
        result = introspect::EditEffect(std::atoi(in.c_str()));
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
