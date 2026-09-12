//  ShearEffect.cpp -- see ShearEffect.h.

#include "IllustratorSDK.h"
#include "ShearEffect.h"
#include "ShearMath.h"
#include "ShearDialog.h"
#include "LiveShearSuites.h"
#include "LiveShearID.h"
#include "ShearLog.h"

#include <sstream>
#include <iomanip>
#include <cmath>

namespace
{
    /** Transform options. Shear is area-preserving and has no uniform scale
        component, so no line scaling is involved; everything else that makes up
        the appearance of the incoming art travels with the geometry. */
    const ai::int32 kShearTransformFlags =
        kTransformObjects |
        kTransformChildren |
        kTransformFillGradients |
        kTransformStrokeGradients |
        kTransformFillPatterns |
        kTransformStrokePatterns |
        kTransformLinkedMasks;
}

void ShearEffect::ReadParameters(ConstAILiveEffectParameters params,
                                 AIReal* shearAngle, AIReal* axisAngle)
{
    *shearAngle = static_cast<AIReal>(kShearDefaultAngle);
    *axisAngle  = static_cast<AIReal>(kShearDefaultAxis);
    if (params == nullptr) return;

    const AIDictKey angleKey = sAIDictionary->Key(kShearAngleKey);
    if (sAIDictionary->IsKnown(params, angleKey))
        sAIDictionary->GetRealEntry(params, angleKey, shearAngle);

    const AIDictKey axisKey = sAIDictionary->Key(kShearAxisKey);
    if (sAIDictionary->IsKnown(params, axisKey))
        sAIDictionary->GetRealEntry(params, axisKey, axisAngle);
}

void ShearEffect::UpdateDisplayString(AILiveEffectParameters params,
                                      AIReal shearAngle, AIReal axisAngle)
{
    if (params == nullptr) return;
    std::ostringstream o;
    o << std::fixed << std::setprecision(1)
      << static_cast<double>(shearAngle) << "\xc2\xb0";
    if (std::fabs(static_cast<double>(axisAngle)) > 1.0e-6)
        o << " / axis " << static_cast<double>(axisAngle) << "\xc2\xb0";
    sAIDictionary->SetStringEntry(params, sAIDictionary->Key(kExtraStringKey), o.str().c_str());
}

ASErr ShearEffect::Go(AILiveEffectGoMessage* message)
{
    if (message == nullptr || message->art == nullptr)
    {
        shearlog::Write("Go: no art");
        return kNoErr;
    }

    AIReal shearAngle = 0, axisAngle = 0;
    ReadParameters(message->parameters, &shearAngle, &axisAngle);

    if (shearlog::Enabled())
    {
        short artType = kUnknownArt;
        sAIArt->GetArtType(message->art, &artType);
        std::ostringstream o;
        o << "Go: artType=" << artType
          << " shear=" << static_cast<double>(shearAngle)
          << " axis=" << static_cast<double>(axisAngle);
        shearlog::Write(o.str());
    }

    if (shear::IsIdentity(shearAngle)) return kNoErr;

    // The anchor is the centre of the incoming art's geometric bounds, which is
    // what Illustrator's own transform commands use when no other reference
    // point is given. Taking it from the art we are handed -- rather than from
    // the source object -- is what makes the effect compose predictably with
    // whatever sits below it in the Appearance stack.
    // Geometric bounds are the stable choice: they do not move when a stroke
    // below us changes weight. Illustrator refuses kControlBounds for art that
    // is not in the document tree, which is exactly the situation a live effect
    // runs in, so fall back to the visible bounds when that happens.
    AIRealRect bounds = { 0, 0, 0, 0 };
    const char* boundsKind = "geometric";
    ASErr err = sAIArt->GetArtTransformBounds(message->art, nullptr,
                                              kControlBounds | kNoExtendedBounds, &bounds);
    if (err)
    {
        boundsKind = "visible";
        err = sAIArt->GetArtBounds(message->art, &bounds);
    }
    if (err)
    {
        shearlog::Write("Go: bounds failed");
        return err;
    }

    AIRealPoint anchor;
    anchor.h = (bounds.left + bounds.right) / 2;
    anchor.v = (bounds.top + bounds.bottom) / 2;

    const AIRealMatrix m = shear::MatrixAbout(shearAngle, axisAngle, anchor);
    err = sAITransformArt->TransformArt(message->art, const_cast<AIRealMatrix*>(&m),
                                        1.0, kShearTransformFlags);

    if (shearlog::Enabled())
    {
        std::ostringstream o;
        o << "Go: bounds=" << boundsKind
          << " anchor=(" << static_cast<double>(anchor.h) << ", " << static_cast<double>(anchor.v)
          << ") matrix=[" << static_cast<double>(m.a) << " " << static_cast<double>(m.b) << " "
          << static_cast<double>(m.c) << " " << static_cast<double>(m.d) << " "
          << static_cast<double>(m.tx) << " " << static_cast<double>(m.ty)
          << "] TransformArt=" << err;
        shearlog::Write(o.str());
    }
    return err;
}

ASErr ShearEffect::EditParameters(AILiveEffectEditParamMessage* message)
{
    if (message == nullptr) return kNoErr;

    AIReal shearAngle = 0, axisAngle = 0;
    ReadParameters(message->parameters, &shearAngle, &axisAngle);

    ShearDialogState state;
    state.shearAngle = static_cast<double>(shearAngle);
    state.axisAngle  = static_cast<double>(axisAngle);
    state.allowPreview = message->allowPreview != 0;
    state.context = message->context;
    state.parameters = message->parameters;

    if (!RunShearDialog(state)) return kCanceledErr;

    sAIDictionary->SetRealEntry(message->parameters, sAIDictionary->Key(kShearAngleKey),
                                static_cast<AIReal>(state.shearAngle));
    sAIDictionary->SetRealEntry(message->parameters, sAIDictionary->Key(kShearAxisKey),
                                static_cast<AIReal>(state.axisAngle));
    UpdateDisplayString(message->parameters,
                        static_cast<AIReal>(state.shearAngle),
                        static_cast<AIReal>(state.axisAngle));

    return sAILiveEffect->UpdateParameters(message->context);
}

ASErr ShearEffect::Interpolate(AILiveEffectInterpParamMessage* message)
{
    if (message == nullptr) return kNoErr;

    AIReal startShear = 0, startAxis = 0, endShear = 0, endAxis = 0;
    ReadParameters(message->startParams, &startShear, &startAxis);
    ReadParameters(message->endParams, &endShear, &endAxis);

    const AIReal t = message->percent;
    const AIReal shearAngle = startShear + (endShear - startShear) * t;
    const AIReal axisAngle  = startAxis  + (endAxis  - startAxis)  * t;

    sAIDictionary->SetRealEntry(message->outParams, sAIDictionary->Key(kShearAngleKey), shearAngle);
    sAIDictionary->SetRealEntry(message->outParams, sAIDictionary->Key(kShearAxisKey), axisAngle);
    UpdateDisplayString(message->outParams, shearAngle, axisAngle);
    return kNoErr;
}
