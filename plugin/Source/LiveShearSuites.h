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

#endif // __LIVESHEARSUITES_H__
