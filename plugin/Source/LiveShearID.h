//  LiveShearID.h -- names, keys, and version numbers of the Shear plugin.
//
//  The identifiers below fall into two kinds. The persistent ones -- the
//  effect's unique name and its parameter keys -- are written into every
//  document that uses the effect, so changing one of them would orphan the
//  effect in artwork that already exists. Treat them as a file format. The rest
//  are display strings and may be changed freely.

#ifndef __LIVESHEARID_H__
#define __LIVESHEARID_H__

#define kLiveShearPluginName        "LiveShear"

/** Product identity. None of it claims any association with Adobe: the SDK's
    own sample defaults name Adobe as the publisher, which would be wrong on a
    third-party binary. */
#define kShearProductName           "Shear for Illustrator"
#define kShearCompanyName           "VulpesNexus"
#define kShearCopyright             "Copyright (C) 2026 VulpesNexus. Licensed under the GNU GPL version 3 or later."
#define kShearDescription           "Non-destructive Shear effect for Adobe Illustrator"
#define kShearHomePage              "https://github.com/VulpesNexus"

/** Release version. Keep in step with the version resource, the README, and
    the name of the distribution archive. */
#define kShearVersionMajor          0
#define kShearVersionMinor          1
#define kShearVersionPatch          0
#define kShearVersionString         "0.1.0-rc.1"

/** PERSISTENT. Unique, non-localized name of the custom live effect, stored in
    saved documents. It must never change once anything has been saved with it;
    a document whose effect name no longer resolves opens with the effect
    inert. */
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

/** Our own group in the Help > About Plug-ins menu. The SDK's defaults put
    third-party plugins under "About SDK Plug-ins" and describe them as Adobe
    samples; the SDK header itself says third parties should add their own. */
#define kShearAboutGroupName        "VulpesNexusAboutPluginsGroupName"
#define kShearAboutGroupTitle       "About VulpesNexus Plug-ins"
#define kShearAboutMenuTitle        "Shear..."

/** PERSISTENT. Parameter dictionary keys of the custom effect. */
#define kShearAngleKey              "shearAngle"
#define kShearAxisKey               "axisAngle"
/** PERSISTENT. Schema number of the parameter block, so a later release can
    recognize what an older one wrote. Absent means schema 1. */
#define kShearSchemaKey             "shearSchema"
#define kShearSchema                1

/** Adding the effect must not move the artwork, so both angles default to
    zero and a freshly applied Shear is the identity until it is edited. */
#define kShearDefaultAngle          0.0
#define kShearDefaultAxis           0.0

#endif // __LIVESHEARID_H__
