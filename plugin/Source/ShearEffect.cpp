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

//  ShearEffect.cpp -- see ShearEffect.h.

#include "IllustratorSDK.h"
#include "ShearEffect.h"
#include "ShearMath.h"
#include "ShearBounds.h"
#include "ShearDialog.h"
#include "LiveShearSuites.h"
#include "LiveShearID.h"
#include "ShearLog.h"

#include <sstream>
#include <iomanip>
#include <locale>
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

    std::string RectText(const AIRealRect& r)
    {
        std::ostringstream o;
        o << std::fixed << std::setprecision(6)
          << "[" << static_cast<double>(r.left) << " " << static_cast<double>(r.top)
          << " " << static_cast<double>(r.right) << " " << static_cast<double>(r.bottom) << "]";
        return o.str();
    }
}

void ShearEffect::ReadParameters(ConstAILiveEffectParameters params,
                                 AIReal* shearAngle, AIReal* axisAngle)
{
    // Everything that reads parameters reads them through here, which is what
    // makes the sanitizing in ShearMath.h unconditional: a hand-edited
    // document, another plugin writing the dictionary, or a value from a future
    // version all arrive along this path.
    double shear = kShearDefaultAngle;
    double axis  = kShearDefaultAxis;

    if (params != nullptr)
    {
        const AIDictKey angleKey = sAIDictionary->Key(kShearAngleKey);
        if (sAIDictionary->IsKnown(params, angleKey))
        {
            AIReal stored = 0;
            if (!sAIDictionary->GetRealEntry(params, angleKey, &stored))
                shear = static_cast<double>(stored);
        }

        const AIDictKey axisKey = sAIDictionary->Key(kShearAxisKey);
        if (sAIDictionary->IsKnown(params, axisKey))
        {
            AIReal stored = 0;
            if (!sAIDictionary->GetRealEntry(params, axisKey, &stored))
                axis = static_cast<double>(stored);
        }
    }

    *shearAngle = static_cast<AIReal>(shear::SanitizeShearAngle(shear));
    *axisAngle  = static_cast<AIReal>(shear::SanitizeAxisAngle(axis));
}

void ShearEffect::WriteParameters(AILiveEffectParameters params,
                                  AIReal shearAngle, AIReal axisAngle)
{
    if (params == nullptr) return;

    const AIReal shear = static_cast<AIReal>(shear::SanitizeShearAngle(shearAngle));
    const AIReal axis  = static_cast<AIReal>(shear::SanitizeAxisAngle(axisAngle));

    sAIDictionary->SetRealEntry(params, sAIDictionary->Key(kShearAngleKey), shear);
    sAIDictionary->SetRealEntry(params, sAIDictionary->Key(kShearAxisKey), axis);
    // A schema number, so a later release that adds a parameter can tell a
    // document written by this one from a document written by itself. Absent
    // means version 1: the two angles, anchored on the center of the incoming
    // art's geometric bounds.
    sAIDictionary->SetIntegerEntry(params, sAIDictionary->Key(kShearSchemaKey), kShearSchema);
    UpdateDisplayString(params, shear, axis);
}

void ShearEffect::UpdateDisplayString(AILiveEffectParameters params,
                                      AIReal shearAngle, AIReal axisAngle)
{
    if (params == nullptr) return;

    // Built as UTF-8 and handed over as a Unicode string rather than through
    // SetStringEntry, which takes a plain char pointer and leaves the encoding
    // to be guessed. The degree sign is the whole reason: guessed wrong, it
    // becomes two half-width katakana on a Japanese Windows.
    std::ostringstream o;
    o.imbue(std::locale::classic());
    o << std::fixed << std::setprecision(1)
      << static_cast<double>(shearAngle) << "\xc2\xb0";
    if (std::fabs(static_cast<double>(axisAngle)) > 1.0e-6)
        o << " / axis " << static_cast<double>(axisAngle) << "\xc2\xb0";

    const ai::UnicodeString text = ai::UnicodeString::FromUTF8(o.str().c_str());
    sAIDictionary->SetUnicodeStringEntry(params, sAIDictionary->Key(kExtraStringKey), text);
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

    // A zero shear is the identity, and the identity is best expressed by not
    // transforming at all. Reevaluating an effect set to zero must leave the
    // art bit for bit as it arrived, however many times it happens.
    if (shear::IsIdentity(shearAngle)) return kNoErr;

    // The reference point is the center of the GEOMETRIC bounds of the art the
    // appearance pipeline handed us, which is the box Illustrator's own shear
    // command anchors on (docs/evidence/anchor.tsv). Taking it from the
    // incoming art rather than from the original object is what makes the
    // effect compose predictably: an effect below us that moves or grows the
    // artwork moves the shear's reference point with it, exactly as stacking
    // two transforms should.
    AIRealRect bounds = { 0, 0, 0, 0 };
    const shear::BoundsRoute route = shear::GeometricBounds(message->art, &bounds);
    if (route == shear::kBoundsFailed)
    {
        // Nothing measurable to shear about. Passing the art through unchanged
        // is the only safe answer; refusing would lose it.
        shearlog::Write("Go: no bounds; art passed through unchanged");
        return kNoErr;
    }

    const AIRealPoint anchor = shear::CenterOf(bounds);
    const AIRealMatrix m = shear::MatrixAbout(shearAngle, axisAngle, anchor);
    if (!shear::IsFiniteMatrix(m))
    {
        shearlog::Write("Go: non-finite matrix refused; art passed through unchanged");
        return kNoErr;
    }

    const ASErr err = sAITransformArt->TransformArt(message->art,
                                                    const_cast<AIRealMatrix*>(&m),
                                                    1.0, kShearTransformFlags);

    if (shearlog::Enabled())
    {
        std::ostringstream o;
        o << "Go: bounds=" << shear::BoundsRouteName(route) << " " << RectText(bounds)
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

    WriteParameters(message->parameters,
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

    const double t = static_cast<double>(message->percent);
    const double shear = startShear + (endShear - startShear) * t;
    const double axis = shear::InterpolateAxisAngle(startAxis, endAxis, t);
    WriteParameters(message->outParams,
                    static_cast<AIReal>(shear), static_cast<AIReal>(axis));

    // Traced because there is no other way to know this ran. Illustrator calls
    // it while building a blend, from inside an operation that hands nothing
    // back to a script, so without this the only evidence would be the shape
    // of the result.
    if (shearlog::Enabled())
    {
        std::ostringstream o;
        o << "Interpolate: t=" << t
          << " shear " << static_cast<double>(startShear) << " -> " << static_cast<double>(endShear) << " = " << shear
          << "; axis " << static_cast<double>(startAxis) << " -> " << static_cast<double>(endAxis) << " = " << axis;
        shearlog::Write(o.str());
    }
    return kNoErr;
}
