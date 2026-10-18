#pragma once
// Not part of the engine's public API: what archive_split.cpp needs from
// archive_engine.cpp so a split ZIP is configured exactly like a plain one.
#include <string>
#include "archive_engine.h"

struct archive;

// Checks the create options the way archiveCreate() does (compression level
// range, method support, method + store, filename encryption) and configures
// `a` for `format`: format, filters, passphrase, compression method and level.
// On failure returns false and sets `*error`; the writer is left for the caller
// to free.
bool archiveConfigureWriter(struct archive* a,
                            ArchiveFormat format,
                            const std::string& passphrase,
                            bool encryptFilenames,
                            int compressionLevel,
                            ArchiveCompressionMethod compressionMethod,
                            std::string* error);
