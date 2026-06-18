#include "stdx/utility.hh"

#include <stdx/config.h>

#if STDX_WINDOWS
#    include <io.h>
#    define ISATTY _isatty
#    define STDOUT_FILENO 1
#else
#    include <unistd.h>
#    define ISATTY isatty
#endif

namespace stdx {

auto is_tty() noexcept -> bool { return ISATTY(STDOUT_FILENO); }

} // namespace stdx
