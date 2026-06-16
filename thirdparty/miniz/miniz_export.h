/* Minimal replacement for the CMake-generated miniz_export.h.
   The project links miniz statically into a single FFI archive, so the
   visibility/DLL-import macros collapse to nothing. */
#ifndef MINIZ_EXPORT_H
#define MINIZ_EXPORT_H

#define MINIZ_EXPORT
#define MINIZ_NO_EXPORT

#endif /* MINIZ_EXPORT_H */
