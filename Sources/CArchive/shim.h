#include <stdint.h>
#include <sys/types.h>

// macOS exports libarchive's stable ABI but does not ship its headers in every
// SDK. Declare only the reader APIs used here; no external library is bundled.
struct archive;
struct archive_entry;
#define ARCHIVE_OK 0
#define ARCHIVE_EOF 1
struct archive *archive_read_new(void);
int archive_read_free(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_tar(struct archive *);
int archive_read_support_format_zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
