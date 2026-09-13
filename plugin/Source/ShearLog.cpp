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

//  ShearLog.cpp -- see ShearLog.h.

#include "IllustratorSDK.h"
#include "ShearLog.h"

#include <cstdlib>
#include <ctime>
#include <fstream>
#include <sstream>

namespace
{
    const char* LogPath()
    {
        static const char* path = std::getenv("LIVESHEAR_LOG");
        return path;
    }
}

namespace shearlog
{

bool Enabled()
{
    return LogPath() != nullptr;
}

void Write(const std::string& line)
{
    const char* path = LogPath();
    if (path == nullptr) return;

    std::ofstream out(path, std::ios::app);
    if (!out) return;

    const std::time_t now = std::time(nullptr);
    std::tm tm;
    localtime_s(&tm, &now);
    char stamp[32];
    std::strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm);
    out << stamp << "  " << line << "\n";
}

std::string Read()
{
    const char* path = LogPath();
    if (path == nullptr) return "Tracing is off. Set LIVESHEAR_LOG before starting Illustrator.\n";

    std::ifstream in(path);
    if (!in) return std::string("No log at ") + path + "\n";
    std::ostringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

} // namespace shearlog
