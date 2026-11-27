#include "ve_drop_target.h"

#include <shellapi.h>

#include <string>
#include <vector>

#include "ve_engine_bridge_win.h"

namespace ve_transfer {

namespace {

std::atomic<IDataObject*> g_own_outbound_data_object{nullptr};
constexpr auto kDragUpdateInterval = std::chrono::milliseconds(33);

// Tells Dart where an own drag is over [hwnd], in client pixels. These events
// are separate from the external drop ones: the files of an own drag are never
// read, Dart finishes it as an in-app drop.
void PostOwnDragEvent(HWND hwnd, int64_t view_id, TransferCallbacksWin* callbacks,
                      const char* method, POINTL pt) {
  if (!callbacks) return;
  POINT client{pt.x, pt.y};
  ScreenToClient(hwnd, &client);
  callbacks->PostDropEvent(view_id, method, static_cast<double>(client.x),
                           static_cast<double>(client.y), {});
}

}  // namespace

// static
void VeDropTarget::SetOwnOutboundDataObject(IDataObject* object) {
  g_own_outbound_data_object.store(object, std::memory_order_release);
}

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
  // Reject our own VeDataObject during outbound DoDragDrop to prevent the
  // "drop files here to import" overlay from firing on the source window.
  if (IsOwnDataObject(pDataObj)) return false;
  FORMATETC fmt{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  return pDataObj->QueryGetData(&fmt) == S_OK;
}

// static
bool VeDropTarget::IsOwnDataObject(IDataObject* pDataObj) {
  if (!pDataObj) return false;
  // Only the active object from our DoDragDrop call is ours. Clipboard
  // privacy formats are public and may also be advertised by external apps.
  IDataObject* active = g_own_outbound_data_object.load(std::memory_order_acquire);
  if (!active) return false;
  if (pDataObj == active) return true;

  // Compare canonical COM identities in case OLE handed us another interface
  // pointer for the same object.
  IUnknown* incoming_identity = nullptr;
  IUnknown* active_identity = nullptr;
  const HRESULT incoming_hr = pDataObj->QueryInterface(
      IID_IUnknown, reinterpret_cast<void**>(&incoming_identity));
  if (FAILED(incoming_hr)) return false;
  const HRESULT active_hr = active->QueryInterface(
      IID_IUnknown, reinterpret_cast<void**>(&active_identity));
  if (FAILED(active_hr)) {
    incoming_identity->Release();
    return false;
  }
  const bool is_own = incoming_identity == active_identity;
  incoming_identity->Release();
  active_identity->Release();
  return is_own;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::DragEnter(
    IDataObject* pDataObj, DWORD, POINTL pt, DWORD* pdwEffect) {
  own_drag_ = IsOwnDataObject(pDataObj);
  if (own_drag_) {
    // The drag that left the app is back over it. It is not an import: say so
    // to Dart, which lets it carry on as an in-app drag. COPY keeps the drag
    // droppable here (with NONE, letting go would not reach Drop).
    can_drop_ = false;
    last_own_drag_update_ = std::chrono::steady_clock::now();
    last_drop_update_ = {};
    if (pdwEffect) *pdwEffect = DROPEFFECT_COPY;
    PostOwnDragEvent(hwnd_, view_id_, callbacks_, "onOwnDragEntered", pt);
    return S_OK;
  }
  can_drop_ = AcceptsDataObject(pDataObj);
  last_own_drag_update_ = {};
  last_drop_update_ = std::chrono::steady_clock::now();
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
  if (own_drag_) {
    if (pdwEffect) *pdwEffect = DROPEFFECT_COPY;
    const auto now = std::chrono::steady_clock::now();
    if (now - last_own_drag_update_ >= kDragUpdateInterval) {
      last_own_drag_update_ = now;
      PostOwnDragEvent(hwnd_, view_id_, callbacks_, "onOwnDragUpdated", pt);
    }
    return S_OK;
  }
  if (pdwEffect) {
    *pdwEffect = can_drop_ ? (*pdwEffect & (DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK))
                           : DROPEFFECT_NONE;
    if (can_drop_ && *pdwEffect == DROPEFFECT_NONE) *pdwEffect = DROPEFFECT_COPY;
  }
  const auto now = std::chrono::steady_clock::now();
  if (can_drop_ && callbacks_ &&
      now - last_drop_update_ >= kDragUpdateInterval) {
    last_drop_update_ = now;
    POINT client{pt.x, pt.y};
    ScreenToClient(hwnd_, &client);
    callbacks_->PostDropEvent(
        view_id_, "onDropUpdated", static_cast<double>(client.x), static_cast<double>(client.y), {});
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::DragLeave() {
  if (own_drag_) {
    own_drag_ = false;
    last_own_drag_update_ = {};
    PostOwnDragEvent(hwnd_, view_id_, callbacks_, "onOwnDragExited", POINTL{0, 0});
    return S_OK;
  }
  const bool was = can_drop_;
  can_drop_ = false;
  last_drop_update_ = {};
  if (was && callbacks_) {
    callbacks_->PostDropEvent(view_id_, "onDropExited", 0.0, 0.0, {});
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE VeDropTarget::Drop(
    IDataObject* pDataObj, DWORD, POINTL pt, DWORD* pdwEffect) {
  can_drop_ = false;
  if (own_drag_) {
    // Let go over the app after leaving it. Dart does the copy or move in-app
    // from the entries it kept: the data object is not read (that would
    // decrypt the files to a temporary folder only to import them back), and
    // the OS drag ends as cancelled, which cleans up whatever it prepared.
    own_drag_ = false;
    last_own_drag_update_ = {};
    if (pdwEffect) *pdwEffect = DROPEFFECT_NONE;
    PostOwnDragEvent(hwnd_, view_id_, callbacks_, "onOwnDragDropped", pt);
    return S_OK;
  }
  last_drop_update_ = {};
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
