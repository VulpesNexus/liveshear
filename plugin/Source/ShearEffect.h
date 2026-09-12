//  ShearEffect.h -- the Shear live effect itself.

#ifndef __SHEAREFFECT_H__
#define __SHEAREFFECT_H__

#include "IllustratorSDK.h"
#include "AILiveEffect.h"

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
};

#endif // __SHEAREFFECT_H__
