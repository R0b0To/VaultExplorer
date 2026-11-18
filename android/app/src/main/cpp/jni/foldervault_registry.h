// The folder-vault bridge (foldervault_bridge.cpp) owns every open vault in a handle
// registry. This is the one way other bridges reach a vault behind a handle: a shared
// view of the same session, not a copy. Whoever closes it first wins -- NativeFolderVault.nativeClose
// or vm::VolumeManager -- and the other side sees fv::Vault::closed() turn true.
#pragma once

#include <jni.h>

#include <memory>

#include "foldervault/fv_vault.h"

// Null for a handle that is unknown or already closed.
std::shared_ptr<fv::Vault> foldervaultShare(jlong handle);
