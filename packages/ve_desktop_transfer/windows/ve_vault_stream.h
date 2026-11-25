#ifndef VE_DESKTOP_TRANSFER_VAULT_STREAM_H_
#define VE_DESKTOP_TRANSFER_VAULT_STREAM_H_

#include <objidl.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <string>

#include "ve_engine_bridge_win.h"

namespace ve_transfer {

// Read-only COM IStream backed directly by ve_open_stream / ve_read_stream / ve_close_stream,
// allowing Windows Explorer to copy decrypted files out of vaults with zero temp files on disk.
class VeVaultStream final : public IStream {
 public:
  VeVaultStream(const EngineBridgeWin* bridge,
                int32_t vol_id,
                std::string vault_path,
                int64_t size_bytes,
                std::atomic<bool>* cancelled);

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // ISequentialStream
  HRESULT STDMETHODCALLTYPE Read(void* pv, ULONG cb, ULONG* pcbRead) override;
  HRESULT STDMETHODCALLTYPE Write(const void* pv, ULONG cb, ULONG* pcbWritten) override;

  // IStream
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER dlibMove,
                                 DWORD dwOrigin,
                                 ULARGE_INTEGER* plibNewPosition) override;
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER libNewSize) override;
  HRESULT STDMETHODCALLTYPE CopyTo(IStream* pstm,
                                   ULARGE_INTEGER cb,
                                   ULARGE_INTEGER* pcbRead,
                                   ULARGE_INTEGER* pcbWritten) override;
  HRESULT STDMETHODCALLTYPE Commit(DWORD grfCommitFlags) override;
  HRESULT STDMETHODCALLTYPE Revert() override;
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER libOffset,
                                       ULARGE_INTEGER cb,
                                       DWORD dwLockType) override;
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER libOffset,
                                         ULARGE_INTEGER cb,
                                         DWORD dwLockType) override;
  HRESULT STDMETHODCALLTYPE Stat(STATSTG* pstatstg, DWORD grfStatFlag) override;
  HRESULT STDMETHODCALLTYPE Clone(IStream** ppstm) override;

 private:
  ~VeVaultStream();
  bool EnsureOpened();

  const EngineBridgeWin* bridge_;
  int32_t vol_id_;
  std::string vault_path_;
  int64_t size_bytes_;
  std::atomic<bool>* cancelled_;
  int64_t stream_handle_ = 0;
  int64_t offset_ = 0;
  std::atomic<ULONG> ref_count_{1};
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_VAULT_STREAM_H_
