//  Introspect.h -- read/write access to Illustrator's live effect registry and
//  to the parameter dictionaries of effects already sitting in an appearance.
//
//  Everything here exists to answer the investigation's questions with host
//  evidence rather than with assumptions about what the SDK ought to do.

#ifndef __INTROSPECT_H__
#define __INTROSPECT_H__

#include "IllustratorSDK.h"
#include <string>

namespace introspect
{
    /** Every effect registered with the running application: unique name,
        localized title, version, preferred input art, style filter flags. */
    std::string DumpLiveEffectRegistry();

    /** What each candidate art-matching specification returns for the current
        selection. Used to pick the one that matches Illustrator's own idea of
        what an effect applies to. */
    std::string DumpSelectionSpecs();

    /** The full appearance of every selected object: pre-effects, paint fields
        with their per-field effects, post-effects, each with a recursive dump
        of its live effect parameter dictionary. */
    std::string DumpSelectionAppearance();

    /** Anchor points and control handles of every selected path, plus bounds.
        The numeric oracle for matrix verification. */
    std::string DumpSelectionGeometry();

    /** Writes one value into the parameter dictionary of the nth post-effect of
        the first selected object, then puts the style back so Illustrator
        re-runs the effect. `type` is one of real, int, bool, string, matrix.
        This is how a latent parameter of a built-in effect would be driven. */
    std::string SetEffectParameter(ai::int32 effectIndex, const std::string& key,
                                   const std::string& type, const std::string& value);

    /** Deletes one key from the nth post-effect's parameter dictionary. */
    std::string DeleteEffectParameter(ai::int32 effectIndex, const std::string& key);

    /** Opens the edit dialog of the nth post-effect of the first selected
        object, exactly as double-clicking the entry in the Appearance panel
        does. Blocks until the dialog is dismissed. */
    std::string EditEffect(ai::int32 effectIndex);

    /** Plays the built-in adobe_shear action event on the current selection with
        explicit parameters, bypassing the dialog. The native-behavior oracle. */
    std::string PlayNativeShear(double shearAngle, double axisAngle,
                                double aboutDX, double aboutDY,
                                bool copy, bool objects, bool patterns);

    /** Geometric bounds of every selected object by each available route,
        so the fallback that walks the art can be held against the host's own
        answer even on artwork where the host answers first. */
    std::string DumpSelectionBounds();
    std::string DumpBoundsFlags();

    /** Moves the nth post-effect of every selected object to another position
        in the stack, which is what dragging an entry in the Appearance panel
        does. */
    std::string MoveEffect(ai::int32 from, ai::int32 to);

    /** Deletes the nth post-effect of every selected object. */
    std::string RemoveEffect(ai::int32 index);

    /** Pre-effect and post-effect counts per selected object, tab separated. */
    std::string CountEffects();

    /** Appends a registered live effect, by unique name, to the appearance of
        every selected object, with parameters parsed from `paramSpec`
        (`key=value` pairs separated by semicolons, values typed as `r:`, `i:`,
        `b:` or `s:`). Used to apply both our own effect and built-in ones. */
    std::string ApplyEffectByName(const std::string& effectName,
                                  const std::string& paramSpec);
}

#endif // __INTROSPECT_H__
