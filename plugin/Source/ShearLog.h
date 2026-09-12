//  ShearLog.h -- a diagnostic trace for the investigation.
//
//  A live effect runs deep inside Illustrator's rendering pipeline, where there
//  is nowhere to put a breakpoint that does not stall the host. Appending a
//  line to a file is crude but it answers the only question that matters during
//  bring-up: was the handler called, with what, and what did it return.
//
//  Tracing is off unless the LIVESHEAR_LOG environment variable names a file.

#ifndef __SHEARLOG_H__
#define __SHEARLOG_H__

#include <string>

namespace shearlog
{
    /** True when a log file was configured for this session. */
    bool Enabled();

    /** Appends one line, with a timestamp. */
    void Write(const std::string& line);

    /** Returns everything logged so far, for the script bridge. */
    std::string Read();
}

#endif // __SHEARLOG_H__
