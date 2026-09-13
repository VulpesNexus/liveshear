//  Introspect.cpp -- see Introspect.h.

#include "IllustratorSDK.h"
#include "Introspect.h"
#include "LiveShearSuites.h"
#include "ShearBounds.h"
#include "LiveShearID.h"

#include "actions/AIObjectAction.h"

#include <sstream>
#include <iomanip>
#include <vector>
#include <cstdlib>
#include <cstdio>
#include <cstring>

namespace
{
    std::string Indent(int depth)
    {
        return std::string(static_cast<size_t>(depth) * 2, ' ');
    }

    std::string Real(AIReal v)
    {
        std::ostringstream o;
        o << std::fixed << std::setprecision(6) << static_cast<double>(v);
        return o.str();
    }

    const char* EntryTypeName(AIEntryType t)
    {
        switch (t)
        {
            case UnknownType:           return "Unknown";
            case IntegerType:           return "Integer";
            case BooleanType:           return "Boolean";
            case RealType:              return "Real";
            case StringType:            return "String";
            case DictType:              return "Dict";
            case ArrayType:             return "Array";
            case BinaryType:            return "Binary";
            case PointType:             return "Point";
            case MatrixType:            return "Matrix";
            case PatternRefType:        return "PatternRef";
            case BrushPatternRefType:   return "BrushPatternRef";
            case CustomColorRefType:    return "CustomColorRef";
            case GradientRefType:       return "GradientRef";
            case PluginObjectRefType:   return "PluginObjectRef";
            case FillStyleType:         return "FillStyle";
            case StrokeStyleType:       return "StrokeStyle";
            case UIDType:               return "UID";
            case UIDREFType:            return "UIDREF";
            case XMLNodeType:           return "XMLNode";
            case SVGFilterType:         return "SVGFilter";
            case ArtStyleType:          return "ArtStyle";
            case SymbolPatternRefType:  return "SymbolPatternRef";
            case GraphDesignRefType:    return "GraphDesignRef";
            case BlendStyleType:        return "BlendStyle";
            case GraphicObjectType:     return "GraphicObject";
            case UnicodeStringType:     return "UnicodeString";
            case PointerType:           return "Pointer";
            case ArtworkPointType:      return "ArtworkPoint";
            case SmoothShadingType:     return "SmoothShading";
            default:                    return "?";
        }
    }

    std::string MatrixText(const AIRealMatrix& m)
    {
        std::ostringstream o;
        o << "[a=" << Real(m.a) << " b=" << Real(m.b)
          << " c=" << Real(m.c) << " d=" << Real(m.d)
          << " tx=" << Real(m.tx) << " ty=" << Real(m.ty) << "]";
        return o.str();
    }

    void DumpDictionary(std::ostringstream& out, ConstAIDictionaryRef dict, int depth);

    void DumpArray(std::ostringstream& out, AIArrayRef array, int depth)
    {
        const ai::int32 n = sAIArray->Size(array);
        for (ai::int32 i = 0; i < n; ++i)
        {
            AIEntryType type = UnknownType;
            sAIArray->GetEntryType(array, i, &type);
            out << Indent(depth) << "[" << i << "] (" << EntryTypeName(type) << ") ";
            switch (type)
            {
                case IntegerType:
                {
                    ai::int32 v = 0;
                    sAIArray->GetIntegerEntry(array, i, &v);
                    out << v;
                    break;
                }
                case BooleanType:
                {
                    ASBoolean v = false;
                    sAIArray->GetBooleanEntry(array, i, &v);
                    out << (v ? "true" : "false");
                    break;
                }
                case RealType:
                {
                    AIReal v = 0;
                    sAIArray->GetRealEntry(array, i, &v);
                    out << Real(v);
                    break;
                }
                case StringType:
                {
                    const char* v = nullptr;
                    sAIArray->GetStringEntry(array, i, &v);
                    out << "\"" << (v ? v : "") << "\"";
                    break;
                }
                case DictType:
                {
                    AIDictionaryRef sub = nullptr;
                    if (!sAIArray->GetDictEntry(array, i, &sub) && sub)
                    {
                        out << "{\n";
                        DumpDictionary(out, sub, depth + 1);
                        out << Indent(depth) << "}";
                        sAIDictionary->Release(sub);
                    }
                    break;
                }
                case MatrixType:
                {
                    AIRealMatrix m;
                    m.Init();
                    if (!sAIEntry->ToRealMatrix(sAIArray->Get(array, i), &m))
                        out << MatrixText(m);
                    break;
                }
                default:
                    out << "<not expanded>";
                    break;
            }
            out << "\n";
        }
    }

    void DumpDictionary(std::ostringstream& out, ConstAIDictionaryRef dict, int depth)
    {
        if (dict == nullptr)
        {
            out << Indent(depth) << "<null dictionary>\n";
            return;
        }
        if (depth > 8)
        {
            out << Indent(depth) << "<recursion limit>\n";
            return;
        }

        out << Indent(depth) << "# " << sAIDictionary->Size(dict) << " entries\n";

        AIDictionaryIterator iter = nullptr;
        if (sAIDictionary->Begin(dict, &iter) || iter == nullptr)
        {
            out << Indent(depth) << "<cannot iterate>\n";
            return;
        }

        for (; !sAIDictionaryIterator->AtEnd(iter); sAIDictionaryIterator->Next(iter))
        {
            const AIDictKey key = sAIDictionaryIterator->GetKey(iter);
            const char* keyName = sAIDictionary->GetKeyString(key);

            AIEntryType type = UnknownType;
            sAIDictionary->GetEntryType(dict, key, &type);

            out << Indent(depth) << (keyName ? keyName : "<null key>")
                << " (" << EntryTypeName(type) << ") = ";

            switch (type)
            {
                case IntegerType:
                {
                    ai::int32 v = 0;
                    sAIDictionary->GetIntegerEntry(dict, key, &v);
                    out << v;
                    break;
                }
                case BooleanType:
                {
                    AIBoolean v = false;
                    sAIDictionary->GetBooleanEntry(dict, key, &v);
                    out << (v ? "true" : "false");
                    break;
                }
                case RealType:
                {
                    AIReal v = 0;
                    sAIDictionary->GetRealEntry(dict, key, &v);
                    out << Real(v);
                    break;
                }
                case StringType:
                {
                    const char* v = nullptr;
                    sAIDictionary->GetStringEntry(dict, key, &v);
                    out << "\"" << (v ? v : "") << "\"";
                    break;
                }
                case UnicodeStringType:
                {
                    ai::UnicodeString v;
                    sAIDictionary->GetUnicodeStringEntry(dict, key, v);
                    out << "\"" << v.as_Platform() << "\"";
                    break;
                }
                case DictType:
                {
                    AIDictionaryRef sub = nullptr;
                    if (!sAIDictionary->GetDictEntry(dict, key, &sub) && sub)
                    {
                        out << "{\n";
                        DumpDictionary(out, sub, depth + 1);
                        out << Indent(depth) << "}";
                        sAIDictionary->Release(sub);
                    }
                    else
                    {
                        out << "<unreadable dict>";
                    }
                    break;
                }
                case ArrayType:
                {
                    AIArrayRef arr = nullptr;
                    if (!sAIDictionary->GetArrayEntry(dict, key, &arr) && arr)
                    {
                        out << "[\n";
                        DumpArray(out, arr, depth + 1);
                        out << Indent(depth) << "]";
                        sAIArray->Release(arr);
                    }
                    break;
                }
                case MatrixType:
                {
                    AIRealMatrix m;
                    m.Init();
                    if (!sAIEntry->ToRealMatrix(sAIDictionary->Get(dict, key), &m))
                        out << MatrixText(m);
                    else
                        out << "<unreadable matrix>";
                    break;
                }
                case PointType:
                case ArtworkPointType:
                {
                    AIRealPoint p = { 0, 0 };
                    if (!sAIEntry->ToRealPoint(sAIDictionary->Get(dict, key), &p))
                        out << "(" << Real(p.h) << ", " << Real(p.v) << ")";
                    break;
                }
                case BinaryType:
                {
                    size_t size = 0;
                    sAIDictionary->GetBinaryEntry(dict, key, nullptr, &size);
                    out << "<" << size << " bytes>";
                    if (size > 0 && size <= 256)
                    {
                        std::vector<unsigned char> buf(size);
                        size_t got = size;
                        if (!sAIDictionary->GetBinaryEntry(dict, key, buf.data(), &got))
                        {
                            out << " ";
                            for (size_t i = 0; i < got; ++i)
                                out << std::hex << std::setw(2) << std::setfill('0')
                                    << static_cast<int>(buf[i]);
                            out << std::dec << std::setfill(' ');
                        }
                    }
                    break;
                }
                default:
                    out << "<not expanded>";
                    break;
            }
            out << "\n";
        }
        sAIDictionaryIterator->Release(iter);
    }

    /** Style filter flags rendered as names. */
    std::string StyleFlagText(ai::int32 flags)
    {
        std::ostringstream o;
        switch (flags & kFilterTypeMask)
        {
            case kPreEffectFilter:  o << "PreEffect";    break;
            case kPostEffectFilter: o << "PostEffect";   break;
            case kStrokeFilter:     o << "StrokeFilter"; break;
            case kFillFilter:       o << "FillFilter";   break;
            default:                o << "type" << (flags & kFilterTypeMask); break;
        }
        if (flags & kSpecialGroupPreFilter)         o << "|SpecialGroupPre";
        if (flags & kHasScalableParams)             o << "|ScalableParams";
        if (flags & kUsesAutoRasterize)             o << "|AutoRasterize";
        if (flags & kCanGenerateSVGFilter)          o << "|SVGFilter";
        if (flags & kHandlesAdjustColorsMsg)        o << "|AdjustColors";
        if (flags & kHandlesIsCompatibleMsg)        o << "|IsCompatible";
        if (flags & kHasDocScaleConvertibleParams)  o << "|DocScaleConvertible";
        if (flags & kParallelExecutionFilter)       o << "|ParallelExecution";
        return o.str();
    }

    /** The objects an effect should be applied to.

        AIMatchingArtSuite::GetSelectedArt returns a flattened hierarchy: select
        one group and it hands back the layer's own group, that group, and every
        path inside it. Applying an effect to all of those would put it on the
        children rather than on the group the user selected, which is not what
        the Appearance panel does. kArtSelectedTopLevelGroups matches only fully
        selected top-level objects, which is the right set. */
    ASErr SelectedTopLevelArt(AIArtHandle*** store, ai::int32* count)
    {
        // None of the ready-made matching specifications does what is wanted
        // here, as the "selection" probe shows: kArtSelected returns a
        // flattened hierarchy that includes the layer's own container,
        // kArtSelectedTopLevelGroups returns only one object however many are
        // selected, and kArtTargeted is right when it is populated but goes
        // empty after some scripted edits.
        //
        // So the set is filtered by hand. Every art object in a layer has that
        // layer's container group as its parent, and only the container itself
        // has no parent, which is how it is recognized and dropped. Of what
        // remains, an object is kept only if none of its ancestors is also in
        // the set -- which keeps a selected group and drops the children
        // Illustrator reports alongside it.
        *store = nullptr;
        *count = 0;

        AIArtHandle** selected = nullptr;
        ai::int32 selectedCount = 0;
        ASErr err = sAIMatchingArt->GetSelectedArt(&selected, &selectedCount);
        if (err) return err;
        if (selected == nullptr || selectedCount == 0)
        {
            if (selected) sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(selected));
            return kNoErr;
        }

        auto inSelection = [&](AIArtHandle art) {
            for (ai::int32 i = 0; i < selectedCount; ++i)
                if ((*selected)[i] == art) return true;
            return false;
        };

        std::vector<AIArtHandle> keep;
        for (ai::int32 i = 0; i < selectedCount; ++i)
        {
            AIArtHandle art = (*selected)[i];
            AIArtHandle parent = nullptr;
            if (sAIArt->GetArtParent(art, &parent) || parent == nullptr) continue;

            bool covered = false;
            for (AIArtHandle a = parent; a != nullptr; )
            {
                AIArtHandle next = nullptr;
                if (sAIArt->GetArtParent(a, &next)) break;
                // The layer container is in the selection set too, and it is
                // the parent of everything, so it must not count as covering.
                if (next != nullptr && inSelection(a)) { covered = true; break; }
                a = next;
            }
            if (!covered) keep.push_back(art);
        }
        sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(selected));

        if (keep.empty()) return kNoErr;

        AIMdMemoryHandle block = nullptr;
        err = sAIMdMemory->MdMemoryNewHandle(
            static_cast<size_t>(keep.size()) * sizeof(AIArtHandle), &block);
        if (err || block == nullptr) return err ? err : kOutOfMemoryErr;

        AIArtHandle** result = reinterpret_cast<AIArtHandle**>(block);
        for (size_t i = 0; i < keep.size(); ++i) (*result)[i] = keep[i];
        *store = result;
        *count = static_cast<ai::int32>(keep.size());
        return kNoErr;
    }

    ASErr FirstSelectedArt(AIArtHandle* art)
    {
        AIArtHandle** store = nullptr;
        ai::int32 count = 0;
        *art = nullptr;
        ASErr err = SelectedTopLevelArt(&store, &count);
        if (err) return err;
        if (count > 0) *art = (*store)[0];
        if (store) sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
        return (*art == nullptr) ? kBadParameterErr : kNoErr;
    }

    void DumpArtStyle(std::ostringstream& out, AIArtStyleHandle style)
    {
        AIStyleParser parser = nullptr;
        if (sAIArtStyleParser->NewParser(&parser) || parser == nullptr)
        {
            out << "  <cannot create style parser>\n";
            return;
        }
        if (sAIArtStyleParser->ParseStyle(parser, style))
        {
            out << "  <cannot parse style>\n";
            sAIArtStyleParser->DisposeParser(parser);
            return;
        }

        ai::int32 n = sAIArtStyleParser->CountPreEffects(parser);
        out << "  pre-effects: " << n << "\n";
        for (ai::int32 i = 0; i < n; ++i)
        {
            AIParserLiveEffect pe = nullptr;
            if (sAIArtStyleParser->GetNthPreEffect(parser, i, &pe) || pe == nullptr) continue;
            const char* name = nullptr;
            ai::int32 major = 0, minor = 0;
            sAIArtStyleParser->GetLiveEffectNameAndVersion(pe, &name, &major, &minor);
            AIBoolean visible = true;
            sAIArtStyleParser->GetEffectVisible(pe, &visible);
            out << "    [" << i << "] \"" << (name ? name : "?") << "\" v"
                << major << "." << minor << (visible ? "" : " (hidden)") << "\n";
            AILiveEffectParameters params = nullptr;
            if (!sAIArtStyleParser->GetLiveEffectParams(pe, &params))
                DumpDictionary(out, params, 3);
        }

        n = sAIArtStyleParser->CountPaintFields(parser);
        out << "  paint fields: " << n << "\n";
        for (ai::int32 i = 0; i < n; ++i)
        {
            AIParserPaintField pf = nullptr;
            if (sAIArtStyleParser->GetNthPaintField(parser, i, &pf) || pf == nullptr) continue;
            const char* name = nullptr;
            ai::int32 major = 0, minor = 0;
            sAIArtStyleParser->GetPaintLiveEffectNameAndVersion(pf, &name, &major, &minor);
            out << "    [" << i << "] paint effect \"" << (name ? name : "(plain paint)")
                << "\" v" << major << "." << minor << "\n";
            const ai::int32 fx = sAIArtStyleParser->CountEffectsOfPaintField(pf);
            out << "        nested effects: " << fx << "\n";
            for (ai::int32 j = 0; j < fx; ++j)
            {
                AIParserLiveEffect pe = nullptr;
                if (sAIArtStyleParser->GetNthEffectOfPaintField(pf, j, &pe) || pe == nullptr) continue;
                const char* en = nullptr;
                ai::int32 emaj = 0, emin = 0;
                sAIArtStyleParser->GetLiveEffectNameAndVersion(pe, &en, &emaj, &emin);
                out << "        [" << j << "] \"" << (en ? en : "?") << "\" v"
                    << emaj << "." << emin << "\n";
                AILiveEffectParameters params = nullptr;
                if (!sAIArtStyleParser->GetLiveEffectParams(pe, &params))
                    DumpDictionary(out, params, 5);
            }
        }

        n = sAIArtStyleParser->CountPostEffects(parser);
        out << "  post-effects: " << n << "\n";
        for (ai::int32 i = 0; i < n; ++i)
        {
            AIParserLiveEffect pe = nullptr;
            if (sAIArtStyleParser->GetNthPostEffect(parser, i, &pe) || pe == nullptr) continue;
            const char* name = nullptr;
            ai::int32 major = 0, minor = 0;
            sAIArtStyleParser->GetLiveEffectNameAndVersion(pe, &name, &major, &minor);
            AIBoolean visible = true;
            sAIArtStyleParser->GetEffectVisible(pe, &visible);
            out << "    [" << i << "] \"" << (name ? name : "?") << "\" v"
                << major << "." << minor << (visible ? "" : " (hidden)") << "\n";
            AILiveEffectParameters params = nullptr;
            if (!sAIArtStyleParser->GetLiveEffectParams(pe, &params))
                DumpDictionary(out, params, 3);
        }

        sAIArtStyleParser->DisposeParser(parser);
    }

    const char* ArtTypeName(short type)
    {
        switch (type)
        {
            case kPathArt:          return "Path";
            case kGroupArt:         return "Group";
            case kCompoundPathArt:  return "CompoundPath";
            case kTextFrameArt:     return "TextFrame";
            case kPlacedArt:        return "Placed";
            case kRasterArt:        return "Raster";
            case kPluginArt:        return "PluginArt";
            case kMeshArt:          return "Mesh";
            case kSymbolArt:        return "Symbol";
            case kForeignArt:       return "Foreign";
            case kLegacyTextArt:    return "LegacyText";
            case kChartArt:         return "Chart";
            default:                return "Other";
        }
    }
}

namespace introspect
{

std::string DumpLiveEffectRegistry()
{
    std::ostringstream out;
    ai::int32 count = 0;
    ASErr err = sAILiveEffect->CountLiveEffects(&count);
    if (err)
    {
        out << "CountLiveEffects failed: " << err << "\n";
        return out.str();
    }
    out << "Registered live effects: " << count << "\n";
    out << "idx\tname\ttitle\tversion\tinputPrefs\tstyleFlags\n";
    for (ai::int32 i = 0; i < count; ++i)
    {
        AILiveEffectHandle effect = nullptr;
        if (sAILiveEffect->GetNthLiveEffect(i, &effect) || effect == nullptr) continue;
        const char* name = nullptr;
        const char* title = nullptr;
        ai::int32 major = 0, minor = 0, input = 0, flags = 0;
        sAILiveEffect->GetLiveEffectName(effect, &name);
        sAILiveEffect->GetLiveEffectTitle(effect, &title);
        sAILiveEffect->GetLiveEffectVersion(effect, &major, &minor);
        sAILiveEffect->GetInputPreference(effect, &input);
        sAILiveEffect->GetStyleFilterFlags(effect, &flags);
        out << i << "\t" << (name ? name : "?") << "\t" << (title ? title : "?")
            << "\t" << major << "." << minor
            << "\t0x" << std::hex << input << std::dec
            << "\t0x" << std::hex << flags << std::dec
            << " " << StyleFlagText(flags) << "\n";
    }
    return out.str();
}

std::string DumpSelectionSpecs()
{
    std::ostringstream out;

    struct Candidate { const char* label; ai::int32 whichAttr; ai::int32 attr; };
    const Candidate candidates[] = {
        { "GetSelectedArt",                         0, 0 },
        { "kArtSelected",                           kArtSelected, kArtSelected },
        { "kArtFullySelected",                      kArtFullySelected, kArtFullySelected },
        { "kArtTargeted",                           kArtTargeted, kArtTargeted },
        { "kArtSelectedTopLevelGroups",             kArtSelectedTopLevelGroups, kArtSelectedTopLevelGroups },
        { "kArtSelected|kArtSelectedTopLevelGroups", kArtSelected | kArtSelectedTopLevelGroups, kArtSelected },
        { "kArtSelectedLeaves",                     kArtSelectedLeaves, kArtSelectedLeaves },
        { "kArtSelected|kArtSelectedLeaves",        kArtSelected | kArtSelectedLeaves, kArtSelected },
    };

    for (const Candidate& c : candidates)
    {
        AIArtHandle** store = nullptr;
        ai::int32 count = 0;
        ASErr err;
        if (c.whichAttr == 0)
        {
            err = sAIMatchingArt->GetSelectedArt(&store, &count);
        }
        else
        {
            AIMatchingArtSpec spec;
            spec.type = kAnyArt;
            spec.whichAttr = c.whichAttr;
            spec.attr = c.attr;
            err = sAIMatchingArt->GetMatchingArt(&spec, 1, &store, &count);
        }
        out << c.label << ": err=" << err << " count=" << count;
        for (ai::int32 i = 0; i < count && store; ++i)
        {
            AIArtHandle art = (*store)[i];
            short type = kUnknownArt;
            sAIArt->GetArtType(art, &type);
            ai::UnicodeString name;
            ASBoolean isDefault = false;
            sAIArt->GetArtName(art, name, &isDefault);
            AIArtHandle parent = nullptr;
            sAIArt->GetArtParent(art, &parent);
            out << "  [" << ArtTypeName(type) << " \"" << name.as_UTF8() << "\""
                << (parent ? " child" : " top") << "]";
        }
        out << "\n";
        if (store) sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    }
    return out.str();
}

std::string DumpSelectionAppearance()
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0)
    {
        out << "No selection.\n";
        return out.str();
    }
    out << "Selected objects: " << count << "\n";
    for (ai::int32 i = 0; i < count; ++i)
    {
        AIArtHandle art = (*store)[i];
        short type = kUnknownArt;
        sAIArt->GetArtType(art, &type);
        ai::UnicodeString name;
        ASBoolean isDefault = false;
        sAIArt->GetArtName(art, name, &isDefault);
        out << "\n[" << i << "] " << ArtTypeName(type) << " \"" << name.as_UTF8() << "\"\n";

        AIRealRect b = { 0, 0, 0, 0 };
        if (!sAIArt->GetArtBounds(art, &b))
            out << "  visible bounds: l=" << Real(b.left) << " t=" << Real(b.top)
                << " r=" << Real(b.right) << " b=" << Real(b.bottom) << "\n";
        AIRealRect g = { 0, 0, 0, 0 };
        if (!sAIArt->GetArtTransformBounds(art, nullptr, kControlBounds | kNoExtendedBounds, &g))
            out << "  geometric bounds: l=" << Real(g.left) << " t=" << Real(g.top)
                << " r=" << Real(g.right) << " b=" << Real(g.bottom) << "\n";

        AIArtStyleHandle style = nullptr;
        if (sAIArtStyle->GetArtStyle(art, &style) || style == nullptr)
        {
            out << "  <no art style>\n";
            continue;
        }
        DumpArtStyle(out, style);
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

std::string DumpSelectionGeometry()
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0)
    {
        out << "No selection.\n";
        return out.str();
    }
    for (ai::int32 i = 0; i < count; ++i)
    {
        AIArtHandle art = (*store)[i];
        short type = kUnknownArt;
        sAIArt->GetArtType(art, &type);
        ai::UnicodeString name;
        ASBoolean isDefault = false;
        sAIArt->GetArtName(art, name, &isDefault);
        out << "[" << i << "] " << ArtTypeName(type) << " \"" << name.as_UTF8() << "\"\n";

        AIRealRect b = { 0, 0, 0, 0 };
        if (!sAIArt->GetArtBounds(art, &b))
            out << "  visible bounds: " << Real(b.left) << " " << Real(b.top) << " "
                << Real(b.right) << " " << Real(b.bottom) << "\n";
        AIRealRect g = { 0, 0, 0, 0 };
        if (!sAIArt->GetArtTransformBounds(art, nullptr, kControlBounds | kNoExtendedBounds, &g))
            out << "  geometric bounds: " << Real(g.left) << " " << Real(g.top) << " "
                << Real(g.right) << " " << Real(g.bottom) << "\n";

        if (type == kPathArt)
        {
            ai::int16 segs = 0;
            sAIPath->GetPathSegmentCount(art, &segs);
            out << "  segments: " << segs << "\n";
            for (ai::int16 s = 0; s < segs; ++s)
            {
                AIPathSegment seg;
                if (sAIPath->GetPathSegments(art, s, 1, &seg)) continue;
                out << "    seg " << s
                    << " p=(" << Real(seg.p.h) << ", " << Real(seg.p.v) << ")"
                    << " in=(" << Real(seg.in.h) << ", " << Real(seg.in.v) << ")"
                    << " out=(" << Real(seg.out.h) << ", " << Real(seg.out.v) << ")"
                    << (seg.corner ? " corner" : "") << "\n";
            }
        }
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

namespace
{
    /** Writes one typed value into a parameter dictionary. */
    ASErr WriteValue(AILiveEffectParameters params, const std::string& key,
                     const std::string& type, const std::string& value, std::string* error)
    {
        const AIDictKey dictKey = sAIDictionary->Key(key.c_str());
        if (type == "real")
            return sAIDictionary->SetRealEntry(params, dictKey, static_cast<AIReal>(std::atof(value.c_str())));
        if (type == "int")
            return sAIDictionary->SetIntegerEntry(params, dictKey, std::atoi(value.c_str()));
        if (type == "bool")
            return sAIDictionary->SetBooleanEntry(params, dictKey, value == "true" || value == "1");
        if (type == "string")
            return sAIDictionary->SetStringEntry(params, dictKey, value.c_str());
        if (type == "matrix")
        {
            double a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;
            if (std::sscanf(value.c_str(), "%lf,%lf,%lf,%lf,%lf,%lf", &a, &b, &c, &d, &tx, &ty) != 6)
            {
                *error = "matrix value must be a,b,c,d,tx,ty";
                return kBadParameterErr;
            }
            AIRealMatrix m;
            m.a = static_cast<AIReal>(a); m.b = static_cast<AIReal>(b);
            m.c = static_cast<AIReal>(c); m.d = static_cast<AIReal>(d);
            m.tx = static_cast<AIReal>(tx); m.ty = static_cast<AIReal>(ty);
            return sAIDictionary->Set(params, dictKey, sAIEntry->FromRealMatrix(&m));
        }
        *error = "unknown type \"" + type + "\"";
        return kBadParameterErr;
    }

    /** Edits the nth post-effect of one object, either setting or deleting a
        key, and puts the rebuilt style back so the effect runs again. */
    bool EditPostEffectParam(AIArtHandle art, ai::int32 effectIndex, const std::string& key,
                             const std::string& type, const std::string& value,
                             bool deleteInstead, std::ostringstream& out)
    {
        AIArtStyleHandle style = nullptr;
        if (sAIArtStyle->GetArtStyle(art, &style) || style == nullptr) return false;

        AIStyleParser parser = nullptr;
        if (sAIArtStyleParser->NewParser(&parser) || parser == nullptr) return false;
        if (sAIArtStyleParser->ParseStyle(parser, style))
        {
            sAIArtStyleParser->DisposeParser(parser);
            return false;
        }

        const ai::int32 n = sAIArtStyleParser->CountPostEffects(parser);
        if (effectIndex < 0 || effectIndex >= n)
        {
            sAIArtStyleParser->DisposeParser(parser);
            return false;
        }

        AIParserLiveEffect pe = nullptr;
        sAIArtStyleParser->GetNthPostEffect(parser, effectIndex, &pe);
        AILiveEffectParameters params = nullptr;
        if (pe == nullptr || sAIArtStyleParser->GetLiveEffectParams(pe, &params) || params == nullptr)
        {
            sAIArtStyleParser->DisposeParser(parser);
            return false;
        }

        const char* effectName = nullptr;
        ai::int32 major = 0, minor = 0;
        sAIArtStyleParser->GetLiveEffectNameAndVersion(pe, &effectName, &major, &minor);

        std::string error;
        ASErr err = deleteInstead
            ? sAIDictionary->DeleteEntry(params, sAIDictionary->Key(key.c_str()))
            : WriteValue(params, key, type, value, &error);

        if (err)
        {
            sAIArtStyleParser->DisposeParser(parser);
            out << "  failed on \"" << (effectName ? effectName : "?") << "\": "
                << (error.empty() ? std::to_string(err) : error) << "\n";
            return false;
        }

        sAIArtStyleParser->SetLiveEffectParams(pe, params);
        AIArtStyleHandle newStyle = nullptr;
        err = sAIArtStyleParser->CreateNewStyle(parser, &newStyle);
        if (!err && newStyle) err = sAIArtStyle->SetArtStyle(art, newStyle);
        sAIArtStyleParser->DisposeParser(parser);

        out << "  " << (deleteInstead ? "deleted " : "set ") << key
            << " on \"" << (effectName ? effectName : "?") << "\" (result " << err << ")\n";
        return err == kNoErr;
    }

    std::string EditSelection(ai::int32 effectIndex, const std::string& key,
                              const std::string& type, const std::string& value,
                              bool deleteInstead)
    {
        std::ostringstream out;
        AIArtHandle** store = nullptr;
        ai::int32 count = 0;
        if (SelectedTopLevelArt(&store, &count) || count == 0)
        {
            out << "No selection.\n";
            return out.str();
        }
        ai::int32 changed = 0;
        for (ai::int32 i = 0; i < count; ++i)
            if (EditPostEffectParam((*store)[i], effectIndex, key, type, value, deleteInstead, out))
                ++changed;
        sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
        out << "Changed " << changed << " of " << count << " selected objects.\n";
        return out.str();
    }
}

std::string SetEffectParameter(ai::int32 effectIndex, const std::string& key,
                               const std::string& type, const std::string& value)
{
    return EditSelection(effectIndex, key, type, value, false);
}

std::string DeleteEffectParameter(ai::int32 effectIndex, const std::string& key)
{
    return EditSelection(effectIndex, key, "", "", true);
}

std::string EditEffect(ai::int32 effectIndex)
{
    std::ostringstream out;
    AIArtHandle art = nullptr;
    if (FirstSelectedArt(&art)) { out << "No selection.\n";  return out.str(); }

    AIArtStyleHandle style = nullptr;
    if (sAIArtStyle->GetArtStyle(art, &style) || style == nullptr)
    { out << "No art style.\n";  return out.str(); }

    AIStyleParser parser = nullptr;
    if (sAIArtStyleParser->NewParser(&parser) || parser == nullptr)
    { out << "Cannot create parser.\n";  return out.str(); }
    if (sAIArtStyleParser->ParseStyle(parser, style))
    { sAIArtStyleParser->DisposeParser(parser); out << "Cannot parse style.\n";  return out.str(); }

    const ai::int32 n = sAIArtStyleParser->CountPostEffects(parser);
    if (effectIndex < 0 || effectIndex >= n)
    {
        sAIArtStyleParser->DisposeParser(parser);
        out << "Post-effect index " << effectIndex << " out of range (" << n << ").\n";
        return out.str();
    }

    AIParserLiveEffect pe = nullptr;
    sAIArtStyleParser->GetNthPostEffect(parser, effectIndex, &pe);
    if (pe == nullptr)
    {
        sAIArtStyleParser->DisposeParser(parser);
        out << "Cannot reach the effect.\n";
        return out.str();
    }

    const ASErr err = sAIArtStyleParser->EditEffectParameters(style, pe);
    sAIArtStyleParser->DisposeParser(parser);
    out << "EditEffectParameters on post-effect " << effectIndex << " returned " << err << "\n";
    return out.str();
}

std::string PlayNativeShear(double shearAngle, double axisAngle,
                            double aboutDX, double aboutDY,
                            bool copy, bool objects, bool patterns)
{
    std::ostringstream out;
    if (!sAIActionManager->IsActionEventRegistered(kAIShearSelectionAction))
    {
        out << "Action event " << kAIShearSelectionAction << " is not registered.\n";
        return out.str();
    }

    AIActionParamValueRef params = nullptr;
    ASErr err = sAIActionManager->AINewActionParamValue(&params);
    if (err) { out << "AINewActionParamValue failed: " << err << "\n"; return out.str(); }

    sAIActionManager->AIActionSetReal(params, kAIShearSelectionShearAngleKey, static_cast<AIReal>(shearAngle));
    sAIActionManager->AIActionSetReal(params, kAIShearSelectionAngleKey, static_cast<AIReal>(axisAngle));
    sAIActionManager->AIActionSetReal(params, kAIShearSelectionAboutDXKey, static_cast<AIReal>(aboutDX));
    sAIActionManager->AIActionSetReal(params, kAIShearSelectionAboutDYKey, static_cast<AIReal>(aboutDY));
    sAIActionManager->AIActionSetBoolean(params, kAIShearSelectionCopyKey, copy);
    sAIActionManager->AIActionSetBoolean(params, kAIShearSelectionObjectsKey, objects);
    sAIActionManager->AIActionSetBoolean(params, kAIShearSelectionPatternsKey, patterns);

    err = sAIActionManager->PlayActionEvent(kAIShearSelectionAction, kDialogOff, params);
    sAIActionManager->AIDeleteActionParamValue(params);

    out << "adobe_shear shear=" << shearAngle << " axis=" << axisAngle
        << " dx=" << aboutDX << " dy=" << aboutDY
        << " copy=" << (copy ? 1 : 0) << " objects=" << (objects ? 1 : 0)
        << " patterns=" << (patterns ? 1 : 0)
        << " -> result " << err << "\n";
    return out.str();
}

std::string ApplyEffectByName(const std::string& effectName, const std::string& paramSpec)
{
    std::ostringstream out;
    AILiveEffectHandle effect = nullptr;
    ASErr err = sAILiveEffect->GetLiveEffectHandleByName(effectName.c_str(), &effect);
    if (err || effect == nullptr)
    {
        out << "No effect named \"" << effectName << "\" (result " << err << ").\n";
        return out.str();
    }

    AILiveEffectParameters params = nullptr;
    err = sAILiveEffect->CreateLiveEffectParameters(&params);
    if (err || params == nullptr)
    {
        out << "CreateLiveEffectParameters failed: " << err << "\n";
        return out.str();
    }

    // paramSpec is "key=r:12.5;other=b:true;name=s:text"
    size_t pos = 0;
    while (pos < paramSpec.size())
    {
        size_t semi = paramSpec.find(';', pos);
        if (semi == std::string::npos) semi = paramSpec.size();
        const std::string pair = paramSpec.substr(pos, semi - pos);
        pos = semi + 1;
        const size_t eq = pair.find('=');
        if (eq == std::string::npos || eq + 2 >= pair.size()) continue;
        const std::string key = pair.substr(0, eq);
        const char tag = pair[eq + 1];
        const std::string val = pair.substr(eq + 3);
        const AIDictKey dictKey = sAIDictionary->Key(key.c_str());
        switch (tag)
        {
            case 'r': sAIDictionary->SetRealEntry(params, dictKey, static_cast<AIReal>(std::atof(val.c_str()))); break;
            case 'i': sAIDictionary->SetIntegerEntry(params, dictKey, std::atoi(val.c_str())); break;
            case 'b': sAIDictionary->SetBooleanEntry(params, dictKey, val == "true" || val == "1"); break;
            case 's': sAIDictionary->SetStringEntry(params, dictKey, val.c_str()); break;
            default: break;
        }
    }

    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0)
    {
        sAIDictionary->Release(params);
        out << "No selection.\n";
        return out.str();
    }

    ai::int32 applied = 0;
    for (ai::int32 i = 0; i < count; ++i)
    {
        AIArtHandle art = (*store)[i];
        short artType = kUnknownArt;
        sAIArt->GetArtType(art, &artType);

        // An object that has never carried an appearance -- a plain group, for
        // instance -- has no art style at all, and GetArtStyle reports success
        // while handing back nothing. Start such an object from an empty style
        // so the effect has something to merge into.
        AIArtStyleHandle style = nullptr;
        ASErr step = sAIArtStyle->GetArtStyle(art, &style);
        if (step)
        {
            out << "  " << ArtTypeName(artType) << ": GetArtStyle failed (" << step << ")\n";
            continue;
        }
        if (style == nullptr)
        {
            AIStyleParser parser = nullptr;
            if (!sAIArtStyleParser->NewParser(&parser) && parser)
            {
                sAIArtStyleParser->CreateNewStyle(parser, &style);
                sAIArtStyleParser->DisposeParser(parser);
            }
            if (style == nullptr)
            {
                out << "  " << ArtTypeName(artType) << ": has no art style and one could not be made\n";
                continue;
            }
        }

        AIArtStyleHandle newStyle = nullptr;
        step = sAILiveEffect->NewArtStyleByMergingLiveEffect(style, effect, params,
                                                             kAppendLiveEffectToStyle, &newStyle);
        if (step || newStyle == nullptr)
        {
            out << "  " << ArtTypeName(artType) << ": NewArtStyleByMergingLiveEffect failed ("
                << step << ")\n";
            continue;
        }

        step = sAIArtStyle->SetArtStyle(art, newStyle);
        if (step)
        {
            out << "  " << ArtTypeName(artType) << ": SetArtStyle failed (" << step << ")\n";
            continue;
        }
        ++applied;
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    sAIDictionary->Release(params);

    out << "Applied \"" << effectName << "\" to " << applied << " of " << count << " objects.\n";
    return out.str();
}


namespace
{
    /** Rebuilds one object's style with its post-effects in a new order, or
        with one of them gone. Reordering an appearance is something a user does
        by dragging in the panel; doing it from a script is how the reorder and
        deletion cases in the release matrix get run at all. */
    std::string RestackOne(AIArtHandle art, ai::int32 from, ai::int32 to, bool remove)
    {
        std::ostringstream out;
        AIArtStyleHandle style = nullptr;
        if (sAIArtStyle->GetArtStyle(art, &style) || style == nullptr)
            return "  no art style\n";

        AIStyleParser parser = nullptr;
        if (sAIArtStyleParser->NewParser(&parser) || parser == nullptr)
            return "  cannot create parser\n";
        if (sAIArtStyleParser->ParseStyle(parser, style))
        {
            sAIArtStyleParser->DisposeParser(parser);
            return "  cannot parse style\n";
        }

        const ai::int32 n = sAIArtStyleParser->CountPostEffects(parser);
        if (from < 0 || from >= n)
        {
            sAIArtStyleParser->DisposeParser(parser);
            out << "  index " << from << " out of range (" << n << " post-effects)\n";
            return out.str();
        }
        // The destination has to be checked too, and separately: removing the
        // effect first leaves n - 1 of them, so n - 1 is a legal destination
        // and means the end. This message arrives from a script, which is to
        // say from outside, and an index the caller made up must not reach the
        // host unexamined.
        if (!remove && (to < 0 || to > n - 1))
        {
            sAIArtStyleParser->DisposeParser(parser);
            out << "  destination " << to << " out of range (0 to " << (n - 1) << ")\n";
            return out.str();
        }

        AIParserLiveEffect effect = nullptr;
        if (sAIArtStyleParser->GetNthPostEffect(parser, from, &effect) || effect == nullptr)
        {
            sAIArtStyleParser->DisposeParser(parser);
            return "  cannot read that effect\n";
        }

        ASErr err = kNoErr;
        if (remove)
        {
            err = sAIArtStyleParser->RemovePostEffect(parser, effect, true);
        }
        else
        {
            // Clone before removing: RemovePostEffect with doDelete frees the
            // original, and without it the caller owns a structure the parser
            // no longer tracks.
            AIParserLiveEffect clone = nullptr;
            err = sAIArtStyleParser->CloneLiveEffect(effect, &clone);
            if (!err && clone != nullptr)
            {
                err = sAIArtStyleParser->RemovePostEffect(parser, effect, true);
                if (!err) err = sAIArtStyleParser->InsertNthPostEffect(parser, to, clone);
                if (err) sAIArtStyleParser->DisposeParserLiveEffect(clone);
            }
        }

        if (!err)
        {
            AIArtStyleHandle newStyle = nullptr;
            err = sAIArtStyleParser->CreateNewStyle(parser, &newStyle);
            if (!err && newStyle) err = sAIArtStyle->SetArtStyle(art, newStyle);
        }
        sAIArtStyleParser->DisposeParser(parser);

        out << "  " << (remove ? "removed " : "moved ") << from;
        if (!remove) out << " to " << to;
        out << " (result " << err << ")\n";
        return out.str();
    }
}

std::string DumpSelectionBounds()
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0) return "No selection.\n";

    out << "index\troute\tleft\ttop\tright\tbottom\n";
    static const shear::BoundsRoute kRoutes[] = {
        shear::kBoundsHostPrecise, shear::kBoundsHost,
        shear::kBoundsComputed, shear::kBoundsVisible
    };
    for (ai::int32 i = 0; i < count; ++i)
    {
        for (const shear::BoundsRoute route : kRoutes)
        {
            AIRealRect r = { 0, 0, 0, 0 };
            out << i << "\t" << shear::BoundsRouteName(route) << "\t";
            if (shear::BoundsByRoute((*store)[i], route, &r))
                out << Real(r.left) << "\t" << Real(r.top) << "\t"
                    << Real(r.right) << "\t" << Real(r.bottom) << "\n";
            else
                out << "refused\t\t\t\n";
        }
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

//  What GetArtTransformBounds actually returns for each combination of the
//  bounds flags, on whatever is selected.
//
//  The SDK's own description of these is not enough to predict the answer.
//  kNoExtendedBounds says it excludes the glyphs of area text and implies
//  kNoStrokeBounds; kControlBounds says that those flags only apply when it is
//  off. Reading that as "kControlBounds | kNoExtendedBounds excludes glyphs"
//  is wrong, and it was wrong here for a while. This prints the table so the
//  choice can be made from what the host does rather than from what the header
//  appears to promise.
std::string DumpBoundsFlags()
{
    struct Combination { const char* name; ai::int32 flags; };
    static const Combination kCombinations[] = {
        { "visible",                        kVisibleBounds },
        { "visible|noStroke",               kVisibleBounds | kNoStrokeBounds },
        { "visible|noExtended",             kVisibleBounds | kNoExtendedBounds },
        { "visible|noStroke|noExtended",    kVisibleBounds | kNoStrokeBounds | kNoExtendedBounds },
        { "control",                        kControlBounds },
        { "control|noStroke",               kControlBounds | kNoStrokeBounds },
        { "control|noExtended",             kControlBounds | kNoExtendedBounds },
        { "control|noStroke|noExtended",    kControlBounds | kNoStrokeBounds | kNoExtendedBounds }
    };

    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0) return "No selection.\n";

    out << "index\tflags\terr\tleft\ttop\tright\tbottom\n";
    for (ai::int32 i = 0; i < count; ++i)
    {
        for (const Combination& c : kCombinations)
        {
            AIRealRect r = { 0, 0, 0, 0 };
            const ASErr err = sAIArt->GetArtTransformBounds((*store)[i], nullptr, c.flags, &r);
            out << i << "\t" << c.name << "\t" << err << "\t";
            if (err) out << "\t\t\t\n";
            else out << Real(r.left) << "\t" << Real(r.top) << "\t"
                     << Real(r.right) << "\t" << Real(r.bottom) << "\n";
        }
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

std::string MoveEffect(ai::int32 from, ai::int32 to)
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0) return "No selection.\n";
    for (ai::int32 i = 0; i < count; ++i) out << RestackOne((*store)[i], from, to, false);
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

std::string RemoveEffect(ai::int32 index)
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0) return "No selection.\n";
    for (ai::int32 i = 0; i < count; ++i) out << RestackOne((*store)[i], index, 0, true);
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

std::string CountEffects()
{
    std::ostringstream out;
    AIArtHandle** store = nullptr;
    ai::int32 count = 0;
    if (SelectedTopLevelArt(&store, &count) || count == 0) return "No selection.\n";
    for (ai::int32 i = 0; i < count; ++i)
    {
        AIArtStyleHandle style = nullptr;
        ai::int32 pre = 0, post = 0;
        if (!sAIArtStyle->GetArtStyle((*store)[i], &style) && style != nullptr)
        {
            AIStyleParser parser = nullptr;
            if (!sAIArtStyleParser->NewParser(&parser) && parser != nullptr)
            {
                if (!sAIArtStyleParser->ParseStyle(parser, style))
                {
                    pre = sAIArtStyleParser->CountPreEffects(parser);
                    post = sAIArtStyleParser->CountPostEffects(parser);
                }
                sAIArtStyleParser->DisposeParser(parser);
            }
        }
        out << i << "\t" << pre << "\t" << post << "\n";
    }
    sAIMdMemory->MdMemoryDisposeHandle(reinterpret_cast<AIMdMemoryHandle>(store));
    return out.str();
}

} // namespace introspect
