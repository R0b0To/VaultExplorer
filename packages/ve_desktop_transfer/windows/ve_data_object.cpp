#include "ve_data_object.h"

#include <shlwapi.h>

#include <cstring>
#include <new>
#include <thread>

#include "ve_vault_stream.h"

namespace ve_transfer {

HGLOBAL AllocHGlobalBytes(const void* data, size_t size) {
  const size_t alloc_size = size == 0 ? 1 : size;
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, alloc_size);
  if (!h) return nullptr;
  if (size > 0 && data != nullptr) {
    void* ptr = GlobalLock(h);
    if (!ptr) {
      GlobalFree(h);
      return nullptr;
    }
    std::memcpy(ptr, data, size);
    GlobalUnlock(h);
  }
  return h;
}

HGLOBAL AllocHGlobalDword(DWORD value) {
  return AllocHGlobalBytes(&value, sizeof(value));
}

VeDataObject::VeDataObject(std::shared_ptr<TransferBatch> batch,
                           const EngineBridgeWin* bridge,
                           TransferCallbacksWin* callbacks,
                           DWORD ui_thread_id)
    : batch_(std::move(batch)),
      bridge_(bridge),
      callbacks_(callbacks),
      ui_thread_id_(ui_thread_id) {
  cf_file_descriptor_w_ = RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW);
  cf_file_contents_ = RegisterClipboardFormatW(CFSTR_FILECONTENTS);
  cf_preferred_drop_effect_ = RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT);
  cf_performed_drop_effect_ = RegisterClipboardFormatW(CFSTR_PERFORMEDDROPEFFECT);
  cf_logical_performed_drop_effect_ = RegisterClipboardFormatW(CFSTR_LOGICALPERFORMEDDROPEFFECT);
  cf_exclude_monitor_ = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
  cf_can_history_ = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
  cf_can_cloud_ = RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
  CoCreateFreeThreadedMarshaler(static_cast<IDataObject*>(this), &ftm_);
}

VeDataObject::~VeDataObject() {
  if (ftm_) {
    ftm_->Release();
    ftm_ = nullptr;
  }
}

bool VeDataObject::IsVirtualMode() const {
  return batch_ && batch_->prefer_virtual_stream && batch_->vol_id >= 0 && !batch_->is_clipboard;
}

HRESULT STDMETHODCALLTYPE VeDataObject::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  if (riid == IID_IUnknown || riid == IID_IDataObject) {
    *ppv = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }
  if (riid == IID_IDataObjectAsyncCapability) {
    *ppv = static_cast<IDataObjectAsyncCapability*>(this);
    AddRef();
    return S_OK;
  }
  if (riid == IID_IMarshal && ftm_ != nullptr) {
    return ftm_->QueryInterface(riid, ppv);
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE VeDataObject::AddRef() {
  return ref_count_.fetch_add(1, std::memory_order_relaxed) + 1;
}

ULONG STDMETHODCALLTYPE VeDataObject::Release() {
  const ULONG remaining = ref_count_.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

HRESULT VeDataObject::BuildDwordMedium(DWORD value, STGMEDIUM* pmedium) {
  HGLOBAL h = AllocHGlobalDword(value);
  if (!h) return E_OUTOFMEMORY;
  pmedium->tymed = TYMED_HGLOBAL;
  pmedium->hGlobal = h;
  pmedium->pUnkForRelease = nullptr;
  return S_OK;
}

bool VeDataObject::EnsureStaged(std::vector<std::wstring>* out_paths) {
  if (!batch_ || !out_paths) return false;

  if (batch_->vol_id < 0) {
    out_paths->clear();
    for (const auto& item : batch_->items) {
      if (!item.local_path.empty()) {
        out_paths->push_back(Utf8ToWide(item.local_path));
      }
    }
    return !out_paths->empty();
  }

  {
    std::lock_guard<std::mutex> lock(batch_->mu);
    if (batch_->realized) {
      *out_paths = batch_->staged_root_paths;
      return !out_paths->empty();
    }
  }
  if (batch_->cancelled.load() || !bridge_ || !bridge_->IsAvailable()) {
    return false;
  }

  std::vector<std::string> utf8_paths;
  bool ok = false;

  const bool on_ui_thread = (GetCurrentThreadId() == ui_thread_id_) && !in_operation_.load();
  if (!on_ui_thread) {
    ok = bridge_->StageBatch(batch_.get(), &utf8_paths);
  } else {
    // Synchronous drop/paste called on STA UI thread: run decryption on a worker
    // thread while pumping paint/timer messages so the Flutter UI never freezes.
    HANDLE done_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!done_event) return false;

    std::thread worker([&]() {
      ok = bridge_->StageBatch(batch_.get(), &utf8_paths);
      SetEvent(done_event);
    });

    for (;;) {
      const DWORD wait = MsgWaitForMultipleObjects(
          1, &done_event, FALSE, 50, QS_PAINT | QS_TIMER | QS_POSTMESSAGE);
      if (wait == WAIT_OBJECT_0) break;
      if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) {
        batch_->cancelled.store(true);
        std::lock_guard<std::mutex> lock(batch_->mu);
        if (batch_->op_id > 0) bridge_->OpCancel(batch_->op_id);
      }
      MSG msg;
      while (PeekMessageW(&msg, nullptr, WM_PAINT, WM_PAINT, PM_REMOVE) ||
             PeekMessageW(&msg, nullptr, WM_TIMER, WM_TIMER, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
      }
    }
    worker.join();
    CloseHandle(done_event);
  }

  if (!ok) return false;

  {
    std::lock_guard<std::mutex> lock(batch_->mu);
    *out_paths = batch_->staged_root_paths;
  }
  if (!realized_notified_.exchange(true) && callbacks_ != nullptr) {
    callbacks_->PostBatchRealized(batch_->batch_id, utf8_paths);
  }
  return !out_paths->empty();
}

bool VeDataObject::EnsureVirtualExpanded() {
  std::lock_guard<std::mutex> lock(virtual_mu_);
  if (virtual_expanded_) return !virtual_entries_.empty();
  virtual_expanded_ = true;
  if (!bridge_ || !batch_) return false;
  return bridge_->ExpandVirtualEntries(batch_->vol_id, batch_->items, &virtual_entries_);
}

HRESULT VeDataObject::BuildHdropMedium(STGMEDIUM* pmedium) {
  std::vector<std::wstring> paths;
  if (!EnsureStaged(&paths)) {
    return batch_ && batch_->cancelled.load() ? E_ABORT : E_FAIL;
  }

  size_t chars = 1;  // double NUL terminator
  for (const auto& path : paths) {
    chars += path.size() + 1;
  }
  const size_t total_bytes = sizeof(DROPFILES) + chars * sizeof(wchar_t);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total_bytes);
  if (!h) return E_OUTOFMEMORY;

  auto* raw = static_cast<uint8_t*>(GlobalLock(h));
  if (!raw) {
    GlobalFree(h);
    return E_OUTOFMEMORY;
  }
  auto* df = reinterpret_cast<DROPFILES*>(raw);
  df->pFiles = sizeof(DROPFILES);
  df->fWide = TRUE;

  auto* dst = reinterpret_cast<wchar_t*>(raw + sizeof(DROPFILES));
  for (const auto& path : paths) {
    const size_t len = path.size() + 1;
    std::memcpy(dst, path.c_str(), len * sizeof(wchar_t));
    dst += len;
  }
  *dst = L'\0';
  GlobalUnlock(h);

  pmedium->tymed = TYMED_HGLOBAL;
  pmedium->hGlobal = h;
  pmedium->pUnkForRelease = nullptr;
  return S_OK;
}

HRESULT VeDataObject::BuildFileDescriptorMedium(STGMEDIUM* pmedium) {
  if (!EnsureVirtualExpanded()) return E_FAIL;

  std::vector<VirtualFileDescriptorEntry> snapshot;
  {
    std::lock_guard<std::mutex> lock(virtual_mu_);
    snapshot = virtual_entries_;
  }
  if (snapshot.empty()) return E_FAIL;

  const size_t count = snapshot.size();
  const size_t total_bytes = sizeof(UINT) + count * sizeof(FILEDESCRIPTORW);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total_bytes);
  if (!h) return E_OUTOFMEMORY;

  auto* fgd = static_cast<FILEGROUPDESCRIPTORW*>(GlobalLock(h));
  if (!fgd) {
    GlobalFree(h);
    return E_OUTOFMEMORY;
  }
  fgd->cItems = static_cast<UINT>(count);
  for (size_t i = 0; i < count; ++i) {
    const auto& src = snapshot[i];
    FILEDESCRIPTORW& fd = fgd->fgd[i];
    fd.dwFlags = FD_ATTRIBUTES | FD_PROGRESSUI;
    fd.dwFileAttributes = src.is_dir
        ? FILE_ATTRIBUTE_DIRECTORY
        : FILE_ATTRIBUTE_NORMAL;
    if (!src.is_dir) {
      fd.dwFlags |= FD_FILESIZE;
      const uint64_t sz = src.size_bytes < 0 ? 0ULL : static_cast<uint64_t>(src.size_bytes);
      fd.nFileSizeHigh = static_cast<DWORD>(sz >> 32);
      fd.nFileSizeLow = static_cast<DWORD>(sz & 0xFFFFFFFFULL);
    }
    if (src.modified_secs > 0) {
      fd.dwFlags |= FD_WRITESTIME;
      fd.ftLastWriteTime = UnixSecondsToFileTime(src.modified_secs);
    }
    const size_t copy_len = (std::min)(src.rel_win_path.size(), static_cast<size_t>(MAX_PATH - 1));
    std::memcpy(fd.cFileName, src.rel_win_path.c_str(), copy_len * sizeof(wchar_t));
    fd.cFileName[copy_len] = L'\0';
  }
  GlobalUnlock(h);

  pmedium->tymed = TYMED_HGLOBAL;
  pmedium->hGlobal = h;
  pmedium->pUnkForRelease = nullptr;
  return S_OK;
}

HRESULT VeDataObject::BuildFileContentsMedium(LONG lindex, STGMEDIUM* pmedium) {
  if (lindex < 0 || !EnsureVirtualExpanded()) return DV_E_LINDEX;

  VirtualFileDescriptorEntry entry;
  {
    std::lock_guard<std::mutex> lock(virtual_mu_);
    const size_t idx = static_cast<size_t>(lindex);
    if (idx >= virtual_entries_.size()) return DV_E_LINDEX;
    entry = virtual_entries_[idx];
  }
  if (entry.is_dir) {
    // Directories are materialized from CFSTR_FILEDESCRIPTORW attributes; return empty stream if queried.
    auto* stream = new (std::nothrow)
        VeVaultStream(bridge_, batch_->vol_id, entry.vault_path, 0, &batch_->cancelled);
    if (!stream) return E_OUTOFMEMORY;
    pmedium->tymed = TYMED_ISTREAM;
    pmedium->pstm = stream;
    pmedium->pUnkForRelease = nullptr;
    return S_OK;
  }
  auto* stream = new (std::nothrow) VeVaultStream(
      bridge_, batch_->vol_id, entry.vault_path, entry.size_bytes, &batch_->cancelled);
  if (!stream) return E_OUTOFMEMORY;
  pmedium->tymed = TYMED_ISTREAM;
  pmedium->pstm = stream;
  pmedium->pUnkForRelease = nullptr;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::QueryGetData(FORMATETC* pformatetc) {
  if (!pformatetc) return E_INVALIDARG;
  if (pformatetc->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;

  const CLIPFORMAT cf = pformatetc->cfFormat;
  if (!IsVirtualMode() && cf == CF_HDROP) {
    return (pformatetc->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_TYMED;
  }
  if (IsVirtualMode() && cf == cf_file_descriptor_w_) {
    return (pformatetc->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_TYMED;
  }
  if (IsVirtualMode() && cf == cf_file_contents_) {
    return (pformatetc->tymed & TYMED_ISTREAM) ? S_OK : DV_E_TYMED;
  }
  if (cf == cf_preferred_drop_effect_) {
    return (pformatetc->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_TYMED;
  }
  if (batch_ && batch_->is_sensitive &&
      (cf == cf_exclude_monitor_ || cf == cf_can_history_ || cf == cf_can_cloud_)) {
    return (pformatetc->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_TYMED;
  }
  return DV_E_FORMATETC;
}

HRESULT STDMETHODCALLTYPE VeDataObject::GetData(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) {
  if (!pformatetcIn || !pmedium) return E_INVALIDARG;
  std::memset(pmedium, 0, sizeof(STGMEDIUM));

  const HRESULT valid = QueryGetData(pformatetcIn);
  if (FAILED(valid)) return valid;

  const CLIPFORMAT cf = pformatetcIn->cfFormat;
  if (!IsVirtualMode() && cf == CF_HDROP) {
    return BuildHdropMedium(pmedium);
  }
  if (IsVirtualMode() && cf == cf_file_descriptor_w_) {
    return BuildFileDescriptorMedium(pmedium);
  }
  if (IsVirtualMode() && cf == cf_file_contents_) {
    return BuildFileContentsMedium(pformatetcIn->lindex, pmedium);
  }
  if (cf == cf_preferred_drop_effect_) {
    return BuildDwordMedium(DROPEFFECT_COPY, pmedium);
  }
  if (cf == cf_exclude_monitor_) {
    return BuildDwordMedium(1, pmedium);
  }
  if (cf == cf_can_history_ || cf == cf_can_cloud_) {
    return BuildDwordMedium(0, pmedium);
  }
  return DV_E_FORMATETC;
}

HRESULT STDMETHODCALLTYPE VeDataObject::GetDataHere(FORMATETC*, STGMEDIUM*) {
  return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE VeDataObject::GetCanonicalFormatEtc(
    FORMATETC* pformatectIn, FORMATETC* pformatetcOut) {
  if (!pformatetcOut) return E_INVALIDARG;
  if (pformatectIn) *pformatetcOut = *pformatectIn;
  pformatetcOut->ptd = nullptr;
  return DATA_S_SAMEFORMATETC;
}

HRESULT STDMETHODCALLTYPE VeDataObject::SetData(
    FORMATETC* pformatetc, STGMEDIUM* pmedium, BOOL fRelease) {
  if (!pformatetc || !pmedium) return E_INVALIDARG;
  // Shell sends CFSTR_PERFORMEDDROPEFFECT / CFSTR_LOGICALPERFORMEDDROPEFFECT after copy.
  if (fRelease) ReleaseStgMedium(pmedium);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::EnumFormatEtc(
    DWORD dwDirection, IEnumFORMATETC** ppenumFormatEtc) {
  if (!ppenumFormatEtc) return E_INVALIDARG;
  *ppenumFormatEtc = nullptr;
  if (dwDirection != DATADIR_GET) return E_NOTIMPL;

  std::vector<FORMATETC> formats;
  if (IsVirtualMode()) {
    formats.push_back({static_cast<CLIPFORMAT>(cf_file_descriptor_w_), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
    formats.push_back({static_cast<CLIPFORMAT>(cf_file_contents_), nullptr, DVASPECT_CONTENT, -1, TYMED_ISTREAM});
  } else {
    formats.push_back({CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
  }
  formats.push_back({static_cast<CLIPFORMAT>(cf_preferred_drop_effect_), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
  if (batch_ && batch_->is_sensitive) {
    formats.push_back({static_cast<CLIPFORMAT>(cf_exclude_monitor_), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
    formats.push_back({static_cast<CLIPFORMAT>(cf_can_history_), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
    formats.push_back({static_cast<CLIPFORMAT>(cf_can_cloud_), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
  }
  return SHCreateStdEnumFmtEtc(static_cast<UINT>(formats.size()), formats.data(), ppenumFormatEtc);
}

HRESULT STDMETHODCALLTYPE VeDataObject::DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) {
  return OLE_E_ADVISENOTSUPPORTED;
}

HRESULT STDMETHODCALLTYPE VeDataObject::DUnadvise(DWORD) {
  return OLE_E_ADVISENOTSUPPORTED;
}

HRESULT STDMETHODCALLTYPE VeDataObject::EnumDAdvise(IEnumSTATDATA**) {
  return OLE_E_ADVISENOTSUPPORTED;
}

HRESULT STDMETHODCALLTYPE VeDataObject::SetAsyncMode(BOOL fDoOpAsync) {
  async_mode_.store(fDoOpAsync != FALSE);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::GetAsyncMode(BOOL* pfIsOpAsync) {
  if (!pfIsOpAsync) return E_INVALIDARG;
  *pfIsOpAsync = async_mode_.load() ? TRUE : FALSE;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::StartOperation(IBindCtx*) {
  in_operation_.store(true);
  async_started_.store(true);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::InOperation(BOOL* pfInAsyncOp) {
  if (!pfInAsyncOp) return E_INVALIDARG;
  *pfInAsyncOp = in_operation_.load() ? TRUE : FALSE;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDataObject::EndOperation(HRESULT hResult, IBindCtx*, DWORD) {
  in_operation_.store(false);
  if (callbacks_ != nullptr && batch_ != nullptr) {
    callbacks_->PostBatchTransferFinished(
        batch_->batch_id, SUCCEEDED(hResult), /*immediate_if_unused=*/true);
  }
  return S_OK;
}

// ── VeDropSource ─────────────────────────────────────────────────────────────

HRESULT STDMETHODCALLTYPE VeDropSource::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  if (riid == IID_IUnknown || riid == IID_IDropSource) {
    *ppv = static_cast<IDropSource*>(this);
    AddRef();
    return S_OK;
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE VeDropSource::AddRef() {
  return ref_count_.fetch_add(1, std::memory_order_relaxed) + 1;
}

ULONG STDMETHODCALLTYPE VeDropSource::Release() {
  const ULONG remaining = ref_count_.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

HRESULT STDMETHODCALLTYPE VeDropSource::QueryContinueDrag(
    BOOL fEscapePressed, DWORD grfKeyState) {
  if (fEscapePressed) return DRAGDROP_S_CANCEL;
  if ((grfKeyState & (MK_LBUTTON | MK_RBUTTON)) == 0) return DRAGDROP_S_DROP;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropSource::GiveFeedback(DWORD) {
  return DRAGDROP_S_USEDEFAULTCURSORS;
}

}  // namespace ve_transfer
