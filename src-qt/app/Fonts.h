#pragma once

#include <QString>

namespace ymusic::fonts {

/// Makes "Material Symbols Rounded" available from system fonts or beside the executable.
void loadIconFont();
/// Returns "Material Symbols Rounded".
QString iconFamily();

/// Makes Google Sans Flex available from system fonts or beside the executable.
void loadInterfaceFont();
/// Returns the first installed UI family (Google Sans Flex, Google Sans, Rubik, Inter, Noto Sans, or system default).
QString interfaceFamily();
/// Returns the platform fixed-width font family.
QString fixedFamily();

} // namespace ymusic::fonts
