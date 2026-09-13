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

//  LiveShearSuites.cpp -- suite import table.

#include "IllustratorSDK.h"
#include "LiveShearSuites.h"

extern "C"
{
    AIMenuSuite*                sAIMenu = nullptr;
    AIUnicodeStringSuite*       sAIUnicodeString = nullptr;
    SPBlocksSuite*              sSPBlocks = nullptr;
    AILiveEffectSuite*          sAILiveEffect = nullptr;
    AIDictionarySuite*          sAIDictionary = nullptr;
    AIDictionaryIteratorSuite*  sAIDictionaryIterator = nullptr;
    AIEntrySuite*               sAIEntry = nullptr;
    AIArraySuite*               sAIArray = nullptr;
    AIArtSuite*                 sAIArt = nullptr;
    AIArtSetSuite*              sAIArtSet = nullptr;
    AIPathSuite*                sAIPath = nullptr;
    AIMatchingArtSuite*         sAIMatchingArt = nullptr;
    AIMdMemorySuite*            sAIMdMemory = nullptr;
    AITransformArtSuite*        sAITransformArt = nullptr;
    AIRealMathSuite*            sAIRealMath = nullptr;
    AIArtStyleSuite*            sAIArtStyle = nullptr;
    AIArtStyleParserSuite*      sAIArtStyleParser = nullptr;
    AIActionManagerSuite*       sAIActionManager = nullptr;
    AIDocumentSuite*            sAIDocument = nullptr;
    AIPreferenceSuite*          sAIPreference = nullptr;
    AIStringFormatUtilsSuite*   sAIStringFormatUtils = nullptr;
    AIUndoSuite*                sAIUndo = nullptr;
    AIUIThemeSuite*             sAIUITheme = nullptr;
};

ImportSuite gImportSuites[] =
{
    kAIMenuSuite,               kAIMenuSuiteVersion,            &sAIMenu,
    kAIUnicodeStringSuite,      kAIUnicodeStringSuiteVersion,   &sAIUnicodeString,
    kSPBlocksSuite,             kSPBlocksSuiteVersion,          &sSPBlocks,
    kAILiveEffectSuite,         kAILiveEffectVersion,           &sAILiveEffect,
    kAIDictionarySuite,         kAIDictionaryVersion,           &sAIDictionary,
    kAIDictionaryIteratorSuite, kAIDictionaryIteratorVersion,   &sAIDictionaryIterator,
    kAIEntrySuite,              kAIEntryVersion,                &sAIEntry,
    kAIArraySuite,              kAIArrayVersion,                &sAIArray,
    kAIArtSuite,                kAIArtVersion,                  &sAIArt,
    kAIArtSetSuite,             kAIArtSetVersion,               &sAIArtSet,
    kAIPathSuite,               kAIPathSuiteVersion,            &sAIPath,
    kAIMatchingArtSuite,        kAIMatchingArtSuiteVersion,     &sAIMatchingArt,
    kAIMdMemorySuite,           kAIMdMemorySuiteVersion,        &sAIMdMemory,
    kAITransformArtSuite,       kAITransformArtVersion,         &sAITransformArt,
    kAIRealMathSuite,           kAIRealMathVersion,             &sAIRealMath,
    kAIArtStyleSuite,           kAIArtStyleVersion,             &sAIArtStyle,
    kAIArtStyleParserSuite,     kAIArtStyleParserVersion,       &sAIArtStyleParser,
    kAIActionManagerSuite,      kAIActionManagerVersion,        &sAIActionManager,
    kAIDocumentSuite,           kAIDocumentVersion,             &sAIDocument,
    kAIPreferenceSuite,         kAIPreferenceVersion,           &sAIPreference,
    kAIStringFormatUtilsSuite,  kAIStringFormatUtilsVersion,    &sAIStringFormatUtils,
    kAIUndoSuite,               kAIUndoVersion,                 &sAIUndo,

    // Everything past this marker is optional: if the host does not
    // have it, the pointer stays null and the plugin still loads.
    nullptr,                    kStartOptionalSuites,           nullptr,
    kAIUIThemeSuite,            kAIUIThemeVersion,              &sAIUITheme,

    nullptr, kEndAllSuites, nullptr
};

// End LiveShearSuites.cpp
