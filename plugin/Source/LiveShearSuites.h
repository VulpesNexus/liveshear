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

//  LiveShearSuites.h -- suites used by the Live Shear investigation plugin.

#ifndef __LIVESHEARSUITES_H__
#define __LIVESHEARSUITES_H__

#include "IllustratorSDK.h"
#include "Suites.hpp"

#include "AILiveEffect.h"
#include "AIArtStyle.h"
#include "AIArtStyleParser.h"
#include "AIEntry.h"
#include "AIArray.h"
#include "AITransformArt.h"
#include "AIActionManager.h"
#include "AIRealMath.h"
#include "AIStringFormatUtils.h"
#include "AIDocument.h"
#include "AIArtSet.h"
#include "AIUITheme.h"

extern "C" AIMenuSuite*                 sAIMenu;
extern "C" AIUnicodeStringSuite*        sAIUnicodeString;
extern "C" SPBlocksSuite*               sSPBlocks;
extern "C" AILiveEffectSuite*           sAILiveEffect;
extern "C" AIDictionarySuite*           sAIDictionary;
extern "C" AIDictionaryIteratorSuite*   sAIDictionaryIterator;
extern "C" AIEntrySuite*                sAIEntry;
extern "C" AIArraySuite*                sAIArray;
extern "C" AIArtSuite*                  sAIArt;
extern "C" AIArtSetSuite*               sAIArtSet;
extern "C" AIPathSuite*                 sAIPath;
extern "C" AIMatchingArtSuite*          sAIMatchingArt;
extern "C" AIMdMemorySuite*             sAIMdMemory;
extern "C" AITransformArtSuite*         sAITransformArt;
extern "C" AIRealMathSuite*             sAIRealMath;
extern "C" AIArtStyleSuite*             sAIArtStyle;
extern "C" AIArtStyleParserSuite*       sAIArtStyleParser;
extern "C" AIActionManagerSuite*        sAIActionManager;
extern "C" AIDocumentSuite*             sAIDocument;
extern "C" AIPreferenceSuite*           sAIPreference;
extern "C" AIStringFormatUtilsSuite*    sAIStringFormatUtils;
extern "C" AIUndoSuite*                 sAIUndo;

// Optional. Illustrator has reported its own interface colors for a long
// time, but a host that did not would otherwise refuse to load the plugin over
// a detail of how one dialog is painted. This one is allowed to be absent, and
// the dialog falls back to the system colors when it is.
extern "C" AIUIThemeSuite*              sAIUITheme;

#endif // __LIVESHEARSUITES_H__
