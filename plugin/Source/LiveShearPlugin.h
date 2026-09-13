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

//  LiveShearPlugin.h -- plugin entry object.

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
