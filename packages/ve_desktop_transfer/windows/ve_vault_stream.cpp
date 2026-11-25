#include "ve_vault_stream.h"

#include <algorithm>
#include <cstring>
#include <new>

namespace ve_transfer {

VeVaultStream::VeVaultStream(const EngineBridgeWin* bridge,
                             int32_t vol_id,
                             std::string vault_path,
                             int64_t size_bytes,
                             std::atomic<bool>* cancelled)
    : bridge_(bridge),
      vol_id_(vol_id),
      vault_path_(std::move(vault_path)),
      size_bytes_(size_bytes < 0 ? 0 : size_bytes),
      cancelled_(cancelled) {}

VeVaultStream::~VeVaultStream() {
  if (stream_handle_ != 0 && bridge_ != nullptr) {
    bridge_->CloseStream(vol_id_, stream_handle_);
    stream_handle_ = 0;
  }
}

HRESULT STDMETHODCALLTYPE VeVaultStream::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  if (riid == IID_IUnknown || riid == IID_ISequentialStream || riid == IID_IStream) {
    *ppv = static_cast<IStream*>(this);
    AddRef();
    return S_OK;
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE VeVaultStream::AddRef() {
  return ref_count_.fetch_add(1, std::memory_order_relaxed) + 1;
}

ULONG STDMETHODCALLTYPE VeVaultStream::Release() {
  const ULONG remaining = ref_count_.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

bool VeVaultStream::EnsureOpened() {
  if (stream_handle_ != 0) return true;
  if (!bridge_ || !bridge_->IsAvailable() || vol_id_ < 0) return false;
  if (cancelled_ && cancelled_->load()) return false;
  if (size_bytes_ == 0) return true;  // 0-byte files need no open stream
  stream_handle_ = bridge_->OpenStream(vol_id_, vault_path_.c_str());
  return stream_handle_ != 0;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Read(void* pv, ULONG cb, ULONG* pcbRead) {
  if (!pv && cb > 0) return STG_E_INVALIDPOINTER;
  if (pcbRead) *pcbRead = 0;
  if (cb == 0) return S_OK;
  if (cancelled_ && cancelled_->load()) return E_ABORT;
  if (offset_ >= size_bytes_) return S_FALSE;
  if (!EnsureOpened()) return STG_E_ACCESSDENIED;

  constexpr ULONG kMaxStep = 4u * 1024u * 1024u;
  ULONG total_read = 0;
  auto* dst = static_cast<uint8_t*>(pv);
  while (total_read < cb && offset_ < size_bytes_) {
    if (cancelled_ && cancelled_->load()) return E_ABORT;
    const int64_t remaining = size_bytes_ - offset_;
    const ULONG want = std::min<ULONG>(
        cb - total_read,
        static_cast<ULONG>(std::min<int64_t>(remaining, kMaxStep)));
    if (want == 0) break;
    const int32_t got = bridge_->ReadStream(
        vol_id_,
        stream_handle_,
        offset_,
        dst + total_read,
        static_cast<int32_t>(want));
    if (got < 0) return E_FAIL;
    if (got == 0) break;
    total_read += static_cast<ULONG>(got);
    offset_ += static_cast<int64_t>(got);
  }

  if (pcbRead) *pcbRead = total_read;
  return (total_read < cb) ? S_FALSE : S_OK;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Write(const void*, ULONG, ULONG*) {
  return STG_E_ACCESSDENIED;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Seek(
    LARGE_INTEGER dlibMove, DWORD dwOrigin, ULARGE_INTEGER* plibNewPosition) {
  int64_t base = 0;
  switch (dwOrigin) {
    case STREAM_SEEK_SET:
      base = 0;
      break;
    case STREAM_SEEK_CUR:
      base = offset_;
      break;
    case STREAM_SEEK_END:
      base = size_bytes_;
      break;
    default:
      return STG_E_INVALIDFUNCTION;
  }
  const int64_t next = base + dlibMove.QuadPart;
  if (next < 0) return STG_E_INVALIDFUNCTION;
  offset_ = next;
  if (plibNewPosition) {
    plibNewPosition->QuadPart = static_cast<ULONGLONG>(offset_);
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::SetSize(ULARGE_INTEGER) {
  return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::CopyTo(
    IStream*, ULARGE_INTEGER, ULARGE_INTEGER*, ULARGE_INTEGER*) {
  return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Commit(DWORD) {
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Revert() {
  return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::LockRegion(
    ULARGE_INTEGER, ULARGE_INTEGER, DWORD) {
  return STG_E_INVALIDFUNCTION;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::UnlockRegion(
    ULARGE_INTEGER, ULARGE_INTEGER, DWORD) {
  return STG_E_INVALIDFUNCTION;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Stat(STATSTG* pstatstg, DWORD grfStatFlag) {
  if (!pstatstg) return STG_E_INVALIDPOINTER;
  std::memset(pstatstg, 0, sizeof(STATSTG));
  pstatstg->type = STGTY_STREAM;
  pstatstg->cbSize.QuadPart = static_cast<ULONGLONG>(size_bytes_);
  pstatstg->grfMode = STGM_READ | STGM_SHARE_DENY_NONE;
  if ((grfStatFlag & STATFLAG_NONAME) == 0) {
    const std::wstring wname = Utf8ToWide(vault_path_);
    const size_t bytes = (wname.size() + 1) * sizeof(wchar_t);
    auto* copy = static_cast<wchar_t*>(CoTaskMemAlloc(bytes));
    if (copy) {
      std::memcpy(copy, wname.c_str(), bytes);
      pstatstg->pwcsName = copy;
    }
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeVaultStream::Clone(IStream** ppstm) {
  if (!ppstm) return E_POINTER;
  auto* cloned = new (std::nothrow)
      VeVaultStream(bridge_, vol_id_, vault_path_, size_bytes_, cancelled_);
  if (!cloned) {
    *ppstm = nullptr;
    return E_OUTOFMEMORY;
  }
  cloned->offset_ = offset_;
  *ppstm = cloned;
  return S_OK;
}

}  // namespace ve_transfer
