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
