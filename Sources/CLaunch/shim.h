#include <launch.h>
#include <mach-o/dyld.h>

static inline int morrow_activate_socket(const char * _Nonnull name,
    int * _Nullable * _Nonnull fds, size_t * _Nonnull count) {
    return launch_activate_socket(name, fds, count);
}
