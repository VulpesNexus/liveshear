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
    nullptr, 0, nullptr
};

// End LiveShearSuites.cpp
