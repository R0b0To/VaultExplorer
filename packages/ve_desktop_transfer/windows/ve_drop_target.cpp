#include "ve_drop_target.h"

#include <shellapi.h>

#include <string>
#include <vector>

#include "ve_engine_bridge_win.h"

namespace ve_transfer {

VeDropTarget::VeDropTarget(HWND hwnd, int64_t view_id, TransferCallbacksWin* callbacks)
    : hwnd_(hwnd), view_id_(view_id), callbacks_(callbacks) {}

bool VeDropTarget::Register() {
  if (registered_ || !hwnd_ || !IsWindow(hwnd_)) return false;
  HRESULT hr = RegisterDragDrop(hwnd_, this);
  if (hr == E_OUTOFMEMORY) {
    OleInitialize(nullptr);
    hr = RegisterDragDrop(hwnd_, this);
  }
  registered_ = SUCCEEDED(hr);
  return registered_;
}

void VeDropTarget::Revoke() {
  if (!registered_) return;
  registered_ = false;
  if (hwnd_ && IsWindow(hwnd_)) {
    RevokeDragDrop(hwnd_);
  }
}

HRESULT STDMETHODCALLTYPE VeDropTarget::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  if (riid == IID_IUnknown || riid == IID_IDropTarget) {
    *ppv = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE VeDropTarget::AddRef() {
  return ref_count_.fetch_add(1, std::memory_order_relaxed) + 1;
}

ULONG STDMETHODCALLTYPE VeDropTarget::Release() {
  const ULONG remaining = ref_count_.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

bool VeDropTarget::AcceptsDataObject(IDataObject* pDataObj) const {
  if (!pDataObj) return false;
  FORMATETC fmt{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  return pDataObj->QueryGetData(&fmt) == S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::DragEnter(
    IDataObject* pDataObj, DWORD, POINTL pt, DWORD* pdwEffect) {
  can_drop_ = AcceptsDataObject(pDataObj);
  if (pdwEffect) {
    *pdwEffect = can_drop_ ? (*pdwEffect & (DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK))
                           : DROPEFFECT_NONE;
    if (can_drop_ && *pdwEffect == DROPEFFECT_NONE) *pdwEffect = DROPEFFECT_COPY;
  }
  if (can_drop_ && callbacks_) {
    POINT client{pt.x, pt.y};
    ScreenToClient(hwnd_, &client);
    callbacks_->PostDropEvent(
        view_id_, "onDropEntered", static_cast<double>(client.x), static_cast<double>(client.y), {});
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::DragOver(DWORD, POINTL pt, DWORD* pdwEffect) {
  if (pdwEffect) {
    *pdwEffect = can_drop_ ? (*pdwEffect & (DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK))
                           : DROPEFFECT_NONE;
    if (can_drop_ && *pdwEffect == DROPEFFECT_NONE) *pdwEffect = DROPEFFECT_COPY;
  }
  if (can_drop_ && callbacks_) {
    POINT client{pt.x, pt.y};
    ScreenToClient(hwnd_, &client);
    callbacks_->PostDropEvent(
        view_id_, "onDropUpdated", static_cast<double>(client.x), static_cast<double>(client.y), {});
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::DragLeave() {
  const bool was = can_drop_;
  can_drop_ = false;
  if (was && callbacks_) {
    callbacks_->PostDropEvent(view_id_, "onDropExited", 0.0, 0.0, {});
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::Drop(
    IDataObject* pDataObj, DWORD, POINTL pt, DWORD* pdwEffect) {
  can_drop_ = false;
  std::vector<std::string> paths;
  FORMATETC fmt{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM stg{};
  if (pDataObj && pDataObj->GetData(&fmt, &stg) == S_OK) {
    if (stg.tymed == TYMED_HGLOBAL && stg.hGlobal != nullptr) {
      auto* hdrop = static_cast<HDROP>(GlobalLock(stg.hGlobal));
      if (hdrop != nullptr) {
        const UINT count = DragQueryFileW(hdrop, 0xFFFFFFFFU, nullptr, 0);
        paths.reserve(count);
        for (UINT i = 0; i < count; ++i) {
          const UINT len = DragQueryFileW(hdrop, i, nullptr, 0);
          if (len == 0) continue;
          std::wstring buf(static_cast<size_t>(len) + 1, L'\0');
          if (DragQueryFileW(hdrop, i, &buf[0], len + 1) > 0) {
            buf.resize(len);
            paths.push_back(WideToUtf8(buf));
          }
        }
        GlobalUnlock(stg.hGlobal);
      }
    }
    ReleaseStgMedium(&stg);
  }

  if (pdwEffect) {
    *pdwEffect = paths.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
  }
  if (callbacks_) {
    POINT client{pt.x, pt.y};
    ScreenToClient(hwnd_, &client);
    callbacks_->PostDropEvent(
        view_id_,
        "onDropReceived",
        static_cast<double>(client.x),
        static_cast<double>(client.y),
        std::move(paths));
  }
  return S_OK;
}

}  // namespace ve_transfer
