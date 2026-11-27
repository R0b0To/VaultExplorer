#ifndef VE_DESKTOP_TRANSFER_DROP_TARGET_H_
#define VE_DESKTOP_TRANSFER_DROP_TARGET_H_

#include <oleidl.h>
#include <windows.h>

#include <atomic>
#include <cstdint>

#include "ve_transfer_callbacks_win.h"

namespace ve_transfer {

// Per-HWND COM IDropTarget attached to every registered Flutter view (both main and
// secondary WindowController windows) with full long-path CF_HDROP support.
class VeDropTarget final : public IDropTarget {
 public:
  VeDropTarget(HWND hwnd, int64_t view_id, TransferCallbacksWin* callbacks);

  bool Register();
  void Revoke();

  // The data object of this process's own outbound drag while one is running
  // (null otherwise). The OLE drag is modal and our own windows are valid drop
  // targets for it, so a drag that leaves the app and comes back over it must
  // be recognised as ours without asking the data object anything (asking for
  // the files makes it decrypt them).
  static void SetOwnOutboundDataObject(IDataObject* object);

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDropTarget
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* pDataObj,
                                      DWORD grfKeyState,
                                      POINTL pt,
                                      DWORD* pdwEffect) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD grfKeyState, POINTL pt, DWORD* pdwEffect) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* pDataObj,
                                 DWORD grfKeyState,
                                 POINTL pt,
                                 DWORD* pdwEffect) override;

 private:
  ~VeDropTarget() = default;

  bool AcceptsDataObject(IDataObject* pDataObj) const;
  static bool IsOwnDataObject(IDataObject* pDataObj);

  HWND hwnd_;
  int64_t view_id_;
  TransferCallbacksWin* callbacks_;
  bool registered_ = false;
  bool can_drop_ = false;
  // The drag now over this window is this process's own (see
  // SetOwnOutboundDataObject).
  bool own_drag_ = false;
  std::atomic<ULONG> ref_count_{1};
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_DROP_TARGET_H_
