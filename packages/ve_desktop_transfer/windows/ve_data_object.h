#ifndef VE_DESKTOP_TRANSFER_DATA_OBJECT_H_
#define VE_DESKTOP_TRANSFER_DATA_OBJECT_H_

#include <objidl.h>
#include <shldisp.h>
#include <shlobj.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

#include "ve_engine_bridge_win.h"
#include "ve_transfer_callbacks_win.h"

namespace ve_transfer {

// COM IDataObject + IDataObjectAsyncCapability + FreeThreadedMarshaler supporting:
// * Virtual streaming via CFSTR_FILEDESCRIPTORW + CFSTR_FILECONTENTS (IStream) for zero-disk-temp Shell drops
// * Lazy CF_HDROP materialization on drop/paste via worker thread + non-blocking UI pump
// * Windows 10/11 Clipboard History & Cloud Sync exclusion formats for sensitive vault items
class VeDataObject final : public IDataObject, public IDataObjectAsyncCapability {
 public:
  VeDataObject(std::shared_ptr<TransferBatch> batch,
               const EngineBridgeWin* bridge,
               TransferCallbacksWin* callbacks,
               DWORD ui_thread_id);

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDataObject
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) override;
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC* pformatetc, STGMEDIUM* pmedium) override;
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* pformatetc) override;
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC* pformatectIn,
                                                  FORMATETC* pformatetcOut) override;
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC* pformatetc,
                                    STGMEDIUM* pmedium,
                                    BOOL fRelease) override;
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD dwDirection,
                                          IEnumFORMATETC** ppenumFormatEtc) override;
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC* pformatetc,
                                    DWORD advf,
                                    IAdviseSink* pAdvSink,
                                    DWORD* pdwConnection) override;
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD dwConnection) override;
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA** ppenumAdvise) override;

  // IDataObjectAsyncCapability
  HRESULT STDMETHODCALLTYPE SetAsyncMode(BOOL fDoOpAsync) override;
  HRESULT STDMETHODCALLTYPE GetAsyncMode(BOOL* pfIsOpAsync) override;
  HRESULT STDMETHODCALLTYPE StartOperation(IBindCtx* pbcReserved) override;
  HRESULT STDMETHODCALLTYPE InOperation(BOOL* pfInAsyncOp) override;
  HRESULT STDMETHODCALLTYPE EndOperation(HRESULT hResult,
                                         IBindCtx* pbcReserved,
                                         DWORD dwEffects) override;

  const std::shared_ptr<TransferBatch>& batch() const { return batch_; }
  bool did_async_operation() const { return async_started_.load(); }

 private:
  ~VeDataObject();

  bool IsVirtualMode() const;
  bool EnsureStaged(std::vector<std::wstring>* out_paths);
  bool EnsureVirtualExpanded();
  HRESULT BuildHdropMedium(STGMEDIUM* pmedium);
  HRESULT BuildFileDescriptorMedium(STGMEDIUM* pmedium);
  HRESULT BuildFileContentsMedium(LONG lindex, STGMEDIUM* pmedium);
  static HRESULT BuildDwordMedium(DWORD value, STGMEDIUM* pmedium);

  std::shared_ptr<TransferBatch> batch_;
  const EngineBridgeWin* bridge_;
  TransferCallbacksWin* callbacks_;
  DWORD ui_thread_id_;

  std::atomic<ULONG> ref_count_{1};
  std::atomic<bool> async_mode_{true};
  std::atomic<bool> in_operation_{false};
  std::atomic<bool> async_started_{false};
  std::atomic<bool> realized_notified_{false};

  std::mutex virtual_mu_;
  bool virtual_expanded_ = false;
  std::vector<VirtualFileDescriptorEntry> virtual_entries_;

  IUnknown* ftm_ = nullptr;

  UINT cf_file_descriptor_w_ = 0;
  UINT cf_file_contents_ = 0;
  UINT cf_preferred_drop_effect_ = 0;
  UINT cf_performed_drop_effect_ = 0;
  UINT cf_logical_performed_drop_effect_ = 0;
  UINT cf_exclude_monitor_ = 0;
  UINT cf_can_history_ = 0;
  UINT cf_can_cloud_ = 0;
};

class VeDropSource final : public IDropSource {
 public:
  VeDropSource() = default;

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL fEscapePressed, DWORD grfKeyState) override;
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD dwEffect) override;

 private:
  ~VeDropSource() = default;
  std::atomic<ULONG> ref_count_{1};
};

// Shared clipboard exclusion format helpers.
HGLOBAL AllocHGlobalBytes(const void* data, size_t size);
HGLOBAL AllocHGlobalDword(DWORD value);

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_DATA_OBJECT_H_
