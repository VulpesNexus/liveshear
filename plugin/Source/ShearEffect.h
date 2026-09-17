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

//  ShearEffect.h -- the Shear live effect itself.

#ifndef __SHEAREFFECT_H__
#define __SHEAREFFECT_H__

#include "IllustratorSDK.h"
#include "AILiveEffect.h"
#include "ShearDialogModel.h"

class ShearEffect
{
public:
    ShearEffect() {}

    /** Transforms the art handed to us by the appearance pipeline. */
    ASErr Go(AILiveEffectGoMessage* message);

    /** Collects the shear and axis angles from the user. */
    ASErr EditParameters(AILiveEffectEditParamMessage* message);

    /** Linear interpolation of both angles, for blends. */
    ASErr Interpolate(AILiveEffectInterpParamMessage* message);

    /** Reads the two angles out of a parameter dictionary, filling in defaults
        for anything absent and sanitizing whatever is there. Every read of the
        parameters goes through this. */
    static void ReadParameters(ConstAILiveEffectParameters params,
                               AIReal* shearAngle, AIReal* axisAngle);

    /** Writes both angles, the schema number, and the Appearance panel's
        one-line description. Every write of the parameters goes through this,
        so nothing unsanitized can reach a saved document. */
    static void WriteParameters(AILiveEffectParameters params,
                                AIReal shearAngle, AIReal axisAngle);

    /** Refreshes the Appearance panel's one-line description of the effect. */
    static void UpdateDisplayString(AILiveEffectParameters params,
                                    AIReal shearAngle, AIReal axisAngle);

    /** The values the dialog last committed, which a newly applied effect
        opens with. Exposed so the script bridge can read, set, and forget
        them, and a probe can put back whatever it found. */
    const shear::LastUsed& GetLastUsed() const { return fLastUsed; }
    void SetLastUsed(const shear::LastUsed& lastUsed) { fLastUsed = lastUsed; }

    /** Whether the dialog's Preview box opens ticked, from Illustrator's
        preferences. Ticked when nothing has been saved. */
    static bool ReadPreviewPreference();
    static void WritePreviewPreference(bool enabled);

private:
    shear::LastUsed fLastUsed;
};

#endif // __SHEAREFFECT_H__
