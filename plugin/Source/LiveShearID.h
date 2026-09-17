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
/** What the plugin calls itself in its own window. The product name says "for
    Illustrator" because Windows file properties show it out of context, where
    a bare "Shear" would name nothing; inside Illustrator the context is the
    window it is sitting in, and the qualifier is just noise. */
#define kShearDisplayName           "Shear"
#define kShearCompanyName           "VulpesNexus"
// Named the way the other plugin repositories name it, and saying which
// license the binary is actually distributable under: a bare GPL would not
// cover the Adobe framework sources compiled into it. See LICENSE-EXCEPTION.
#define kShearCopyright             "Copyright (C) 2026 Vixen420. GPL-3.0-or-later, with an Adobe Illustrator SDK linking exception."
#define kShearDescription           "Non-destructive Shear effect for Adobe Illustrator"
#define kShearHomePage              "https://github.com/VulpesNexus"

/* Wide flavors of the same text, for the Windows dialogs. The two-step
   expansion is what makes the argument expand before L is pasted onto it.

   The non-ASCII characters are escapes rather than literal glyphs so every
   source file that uses them stays plain ASCII: this machine's code page is
   932, and a literal copyright sign in a wide literal would be decoded through
   whatever the compiler guessed the file's encoding was. */
#define LS_WIDEN2(x)                L ## x
#define LS_WIDEN(x)                 LS_WIDEN2(x)
#define LS_WDISPLAYNAME             LS_WIDEN(kShearDisplayName)
/* Widened a number at a time. kShearDisplayVersion is three string literals
   side by side, not one token, and the paste above only ever reaches the
   first of them. */
#define LS_WDISPLAYVERSION          LS_WIDEN(LS_STRINGIFY(kShearVersionMajor)) L"." \
                                    LS_WIDEN(LS_STRINGIFY(kShearVersionMinor)) L"." \
                                    LS_WIDEN(LS_STRINGIFY(kShearVersionPatch))

#define LS_COPY                     L"\x00A9"   /* U+00A9 copyright sign */

#define LS_REPO_URL                 L"https://github.com/VulpesNexus/liveshear"
#define LS_AUTHOR_URL               L"https://github.com/VulpesNexus"

/** Release version. Keep in step with the README and the name of the
    distribution archive; the version resource is built from these.

    Two forms, deliberately. kShearVersionString is the build: it carries the
    release-candidate suffix, and it is what the file version, the archive
    name, and the script bridge report, so a downloaded binary can be tied back
    to the release it came from. kShearDisplayVersion is the release: three
    numbers, no suffix, and it is what the About window shows.

    The display form is built from the numbers rather than written out, and the
    two are checked against each other below, so they cannot drift. */
#define kShearVersionMajor          0
#define kShearVersionMinor          1
#define kShearVersionPatch          1
#define kShearVersionString         "0.1.1"

#define LS_STRINGIFY2(x)            #x
#define LS_STRINGIFY(x)             LS_STRINGIFY2(x)
#define kShearDisplayVersion        LS_STRINGIFY(kShearVersionMajor) "." \
                                    LS_STRINGIFY(kShearVersionMinor) "." \
                                    LS_STRINGIFY(kShearVersionPatch)

#ifdef __cplusplus
namespace liveshearid {
    constexpr bool StartsWith(const char* text, const char* prefix)
    {
        return *prefix == '\0' ? true
             : (*text == *prefix && StartsWith(text + 1, prefix + 1));
    }
}
static_assert(liveshearid::StartsWith(kShearVersionString, kShearDisplayVersion),
              "kShearVersionString and the major.minor.patch numbers disagree.");
#endif

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
/* There is no category here on purpose. Illustrator files a third-party
   effect category under a menu group it names "Live 3rd Party " plus the
   category, so a category never joins one of Adobe's own submenus -- it makes
   a second submenu next to it, wearing the same name. The item goes on the
   Effect menu itself instead. See LIVE_SHEAR_INVESTIGATION.md. */

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

/** PERSISTENT, in Illustrator's preferences file rather than in documents:
    whether the dialog's Preview box is ticked. Illustrator keeps the same
    setting for each of its own transform dialogs, under PreviewPref. Renaming
    either string only forgets one tick, so this is a lesser promise than the
    parameter keys above. */
#define kShearPreferencePrefix      "LiveShear"
#define kShearPreviewPreference     "previewEnabled"

#endif // __LIVESHEARID_H__
