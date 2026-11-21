// File-manager sidebar entries for OS mounts (Linux). See ve_mount_places.cpp.
#pragma once

#include <string>

namespace vemount {

// Lists `mountPoint` in Dolphin's Places and in the GTK bookmarks (only the files that already exist).
// Idempotent. Never throws; failures are silent (the mount itself must not depend on this).
void placesAdd(const std::string& mountPoint, const std::string& title);

// Removes what placesAdd listed for `mountPoint`.
void placesRemove(const std::string& mountPoint);

// Removes entries an earlier run left behind (crash, kill -9). Call once per process before mounting.
void placesCleanStale();

}  // namespace vemount
