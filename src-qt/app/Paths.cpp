#include "app/Paths.h"

#include <QDir>
#include <QStandardPaths>

namespace ymusic::paths {

namespace {

QString ensured(const QString &path)
{
    QDir().mkpath(path);
    return path;
}

} // namespace

QString dataDirectory()
{
    return ensured(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                   + QStringLiteral("/ymusic"));
}

QString cacheDirectory()
{
    return ensured(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                   + QStringLiteral("/ymusic"));
}

QString logDirectory()
{
    return ensured(dataDirectory() + QStringLiteral("/logs"));
}

QString logFilePath()
{
    return logDirectory() + QStringLiteral("/ymusic.log");
}

} // namespace ymusic::paths
