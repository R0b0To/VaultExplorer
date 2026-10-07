// Host-test stand-in for ntfs-3g's volume.h: VolumeState only stores an
// `ntfs_volume*`, so an opaque type is enough.
#pragma once
typedef struct ntfs_volume ntfs_volume;
