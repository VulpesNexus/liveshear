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
