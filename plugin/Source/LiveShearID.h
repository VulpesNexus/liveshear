//  LiveShearID.h -- shared constants for the Live Shear investigation plug-in.

#ifndef __LIVESHEARID_H__
#define __LIVESHEARID_H__

#define kLiveShearPluginName        "LiveShear"

/** Unique, non-localized name of the custom live effect. Stored in saved
    documents, so it must never change once anything has been saved with it. */
#define kShearEffectName            "VulpesNexus Shear"
/** Localized name of the effect, shown in the Appearance panel. Adobe's own
    effects register the bare noun here -- the built-in Transform effect is
    "Transform" -- and put the ellipsis only on the menu item. */
#define kShearEffectTitle           "Shear"
/** Menu item text. The ellipsis is the platform convention for a command that
    opens a dialog, and matches Adobe's own "Shear..." under Object > Transform. */
#define kShearEffectMenuTitle       "Shear..."
/** Submenu of the Effect menu the item is added to. */
#define kShearEffectCategory        "Distort & Transform"

/** Parameter dictionary keys of the custom effect. */
#define kShearAngleKey              "shearAngle"
#define kShearAxisKey               "axisAngle"
#define kShearRefKey                "referencePoint"

#define kShearDefaultAngle          0.0
#define kShearDefaultAxis           0.0

#endif // __LIVESHEARID_H__
