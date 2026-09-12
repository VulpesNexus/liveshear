//  LiveShearPlugin.h -- plug-in entry object.

#ifndef __LIVESHEARPLUGIN_H__
#define __LIVESHEARPLUGIN_H__

#include "IllustratorSDK.h"
#include "Plugin.hpp"
#include "LiveShearID.h"
#include "ShearEffect.h"
#include "AIScriptMessage.h"

class LiveShearPlugin : public Plugin
{
public:
    explicit LiveShearPlugin(SPPluginRef pluginRef);
    virtual ~LiveShearPlugin() {}

    FIXUP_VTABLE_EX(LiveShearPlugin, Plugin);

    ASErr Message(char* caller, char* selector, void* message) override;
    ASErr StartupPlugin(SPInterfaceMessage* message) override;
    ASErr ShutdownPlugin(SPInterfaceMessage* message) override;

    ASErr GoLiveEffect(AILiveEffectGoMessage* message) override;
    ASErr EditLiveEffectParameters(AILiveEffectEditParamMessage* message) override;
    ASErr LiveEffectInterpolate(AILiveEffectInterpParamMessage* message) override;

    ASErr GoMenuItem(AIMenuMessage* message) override;

private:
    ASErr AddLiveEffects(SPInterfaceMessage* message);
    ASErr AddMenus(SPInterfaceMessage* message);
    ASErr HandleScriptMessage(const char* selector, AIScriptMessage* message);

    AIMenuItemHandle fAboutPluginMenu;
    AILiveEffectHandle fShearEffect;
    ShearEffect fShear;
};

#endif // __LIVESHEARPLUGIN_H__
