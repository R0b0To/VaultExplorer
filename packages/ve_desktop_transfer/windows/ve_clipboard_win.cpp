#include "ve_clipboard_win.h"

#include <shellapi.h>
#include <shlobj.h>

#include <atomic>
#include <cstring>
#include <new>

namespace ve_transfer {

namespace {

struct ClipboardBlobEntry {
  CLIPFORMAT format = 0;
  std::vector<uint8_t> bytes;
};

// Lightweight COM IDataObject holding prebuilt in-memory clipboard formats
// (images + exclusion flags or sensitive text + exclusion flags).
class VeMemoryDataObject final : public IDataObject {
 public:
  explicit VeMemoryDataObject(std::vector<ClipboardBlobEntry> entries)
      : entries_(std::move(entries)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IDataObject) {
      *ppv = static_cast<IDataObject*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return ref_count_.fetch_add(1, std::memory_order_relaxed) + 1;
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG rem = ref_count_.fetch_sub(1, std::memory_order_acq_rel) - 1;
    if (rem == 0) delete this;
    return rem;
  }

  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* pformatetc) override {
    if (!pformatetc) return E_INVALIDARG;
    if (pformatetc->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;
    if ((pformatetc->tymed & TYMED_HGLOBAL) == 0) return DV_E_TYMED;
    for (const auto& entry : entries_) {
      if (entry.format == pformatetc->cfFormat) return S_OK;
    }
    return DV_E_FORMATETC;
  }

  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) override {
    if (!pformatetcIn || !pmedium) return E_INVALIDARG;
    std::memset(pmedium, 0, sizeof(STGMEDIUM));
    if (pformatetcIn->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;
    if ((pformatetcIn->tymed & TYMED_HGLOBAL) == 0) return DV_E_TYMED;

    for (const auto& entry : entries_) {
      if (entry.format == pformatetcIn->cfFormat) {
        HGLOBAL h = AllocHGlobalBytes(entry.bytes.data(), entry.bytes.size());
        if (!h) return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }
    }
    return DV_E_FORMATETC;
  }

  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(
      FORMATETC* in, FORMATETC* out) override {
    if (!out) return E_INVALIDARG;
    if (in) *out = *in;
    out->ptd = nullptr;
    return DATA_S_SAMEFORMATETC;
  }

  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE EnumFormatEtc(
      DWORD dwDirection, IEnumFORMATETC** ppenum) override {
    if (!ppenum) return E_INVALIDARG;
    *ppenum = nullptr;
    if (dwDirection != DATADIR_GET) return E_NOTIMPL;
    std::vector<FORMATETC> fmts;
    fmts.reserve(entries_.size());
    for (const auto& entry : entries_) {
      fmts.push_back({entry.format, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
    }
    return SHCreateStdEnumFmtEtc(static_cast<UINT>(fmts.size()), fmts.data(), ppenum);
  }

  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  ~VeMemoryDataObject() {
    for (auto& e : entries_) {
      if (!e.bytes.empty()) {
        SecureZeroMemory(e.bytes.data(), e.bytes.size());
      }
    }
  }

  std::vector<ClipboardBlobEntry> entries_;
  std::atomic<ULONG> ref_count_{1};
};

void AppendDwordEntry(std::vector<ClipboardBlobEntry>* entries, UINT cf, DWORD val) {
  if (cf == 0) return;
  ClipboardBlobEntry entry;
  entry.format = static_cast<CLIPFORMAT>(cf);
  entry.bytes.resize(sizeof(DWORD));
  std::memcpy(entry.bytes.data(), &val, sizeof(DWORD));
  entries->push_back(std::move(entry));
}

void AppendExclusionEntries(std::vector<ClipboardBlobEntry>* entries) {
  AppendDwordEntry(
      entries,
      RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing"),
      1);
  AppendDwordEntry(
      entries,
      RegisterClipboardFormatW(L"CanIncludeInClipboardHistory"),
      0);
  AppendDwordEntry(
      entries,
      RegisterClipboardFormatW(L"CanUploadToCloudClipboard"),
      0);
}

std::vector<uint8_t> BuildDibV5FromRgba(
    const uint8_t* rgba, int32_t width, int32_t height) {
  const size_t row_bytes = static_cast<size_t>(width) * 4u;
  const size_t pixel_bytes = row_bytes * static_cast<size_t>(height);
  std::vector<uint8_t> out(sizeof(BITMAPV5HEADER) + pixel_bytes, 0);

  auto* hdr = reinterpret_cast<BITMAPV5HEADER*>(out.data());
  hdr->bV5Size = sizeof(BITMAPV5HEADER);
  hdr->bV5Width = width;
  hdr->bV5Height = height;  // positive = bottom-up DIB
  hdr->bV5Planes = 1;
  hdr->bV5BitCount = 32;
  hdr->bV5Compression = BI_BITFIELDS;
  hdr->bV5SizeImage = static_cast<DWORD>(pixel_bytes);
  hdr->bV5RedMask = 0x00FF0000;
  hdr->bV5GreenMask = 0x0000FF00;
  hdr->bV5BlueMask = 0x000000FF;
  hdr->bV5AlphaMask = 0xFF000000;
  hdr->bV5CSType = LCS_sRGB;

  uint8_t* dst_base = out.data() + sizeof(BITMAPV5HEADER);
  for (int32_t y = 0; y < height; ++y) {
    const uint8_t* src_row = rgba + static_cast<size_t>(height - 1 - y) * row_bytes;
    uint8_t* dst_row = dst_base + static_cast<size_t>(y) * row_bytes;
    for (int32_t x = 0; x < width; ++x) {
      const size_t i = static_cast<size_t>(x) * 4u;
      dst_row[i + 0] = src_row[i + 2];  // B
      dst_row[i + 1] = src_row[i + 1];  // G
      dst_row[i + 2] = src_row[i + 0];  // R
      dst_row[i + 3] = src_row[i + 3];  // A
    }
  }
  return out;
}

std::vector<uint8_t> BuildLegacyDibFromRgba(
    const uint8_t* rgba, int32_t width, int32_t height) {
  const size_t row_bytes = static_cast<size_t>(width) * 4u;
  const size_t pixel_bytes = row_bytes * static_cast<size_t>(height);
  std::vector<uint8_t> out(sizeof(BITMAPINFOHEADER) + pixel_bytes, 0);

  auto* hdr = reinterpret_cast<BITMAPINFOHEADER*>(out.data());
  hdr->biSize = sizeof(BITMAPINFOHEADER);
  hdr->biWidth = width;
  hdr->biHeight = height;  // positive = bottom-up DIB
  hdr->biPlanes = 1;
  hdr->biBitCount = 32;
  hdr->biCompression = BI_RGB;
  hdr->biSizeImage = static_cast<DWORD>(pixel_bytes);

  uint8_t* dst_base = out.data() + sizeof(BITMAPINFOHEADER);
  for (int32_t y = 0; y < height; ++y) {
    const uint8_t* src_row = rgba + static_cast<size_t>(height - 1 - y) * row_bytes;
    uint8_t* dst_row = dst_base + static_cast<size_t>(y) * row_bytes;
    for (int32_t x = 0; x < width; ++x) {
      const size_t i = static_cast<size_t>(x) * 4u;
      // Composite onto white for BI_RGB consumers that ignore alpha (e.g. MS Paint).
      const uint8_t a = src_row[i + 3];
      const uint8_t inv = 255 - a;
      dst_row[i + 0] = static_cast<uint8_t>((src_row[i + 2] * a + 255 * inv) / 255);
      dst_row[i + 1] = static_cast<uint8_t>((src_row[i + 1] * a + 255 * inv) / 255);
      dst_row[i + 2] = static_cast<uint8_t>((src_row[i + 0] * a + 255 * inv) / 255);
      dst_row[i + 3] = 255;
    }
  }
  return out;
}

DWORD ComputeDibPixelOffset(const uint8_t* dib, size_t dib_size) {
  if (dib_size < sizeof(BITMAPINFOHEADER)) return 0;
  const auto* bmi = reinterpret_cast<const BITMAPINFOHEADER*>(dib);
  DWORD header_size = bmi->biSize;
  if (header_size < sizeof(BITMAPINFOHEADER) || header_size > dib_size) {
    header_size = sizeof(BITMAPINFOHEADER);
  }
  DWORD palette_entries = 0;
  if (bmi->biBitCount <= 8) {
    palette_entries = bmi->biClrUsed > 0 ? bmi->biClrUsed : (1u << bmi->biBitCount);
  } else if (bmi->biCompression == BI_BITFIELDS && header_size == sizeof(BITMAPINFOHEADER)) {
    // 3 DWORD color masks follow BITMAPINFOHEADER when BI_BITFIELDS is used without V4/V5.
    return sizeof(BITMAPFILEHEADER) + header_size + 12;
  }
  return sizeof(BITMAPFILEHEADER) + header_size + palette_entries * sizeof(RGBQUAD);
}

}  // namespace

ClipboardWin::ClipboardWin(const EngineBridgeWin* bridge,
                           TransferCallbacksWin* callbacks,
                           DWORD ui_thread_id)
    : bridge_(bridge), callbacks_(callbacks), ui_thread_id_(ui_thread_id) {}

ClipboardWin::~ClipboardWin() {
  ClearOwnedOnShutdown();
}

void ClipboardWin::ReleaseActiveFiles() {
  if (active_files_obj_) {
    active_files_obj_->Release();
    active_files_obj_ = nullptr;
  }
}

void ClipboardWin::ReleaseActiveImage() {
  if (active_image_obj_) {
    active_image_obj_->Release();
    active_image_obj_ = nullptr;
  }
}

void ClipboardWin::ReleaseActiveText() {
  if (active_text_obj_) {
    active_text_obj_->Release();
    active_text_obj_ = nullptr;
  }
  if (!active_sensitive_text_.empty()) {
    SecureZeroMemory(&active_sensitive_text_[0], active_sensitive_text_.size() * sizeof(wchar_t));
    active_sensitive_text_.clear();
  }
  active_sensitive_seq_ = 0;
}

bool ClipboardWin::SetFiles(std::shared_ptr<TransferBatch> batch) {
  if (!batch) return false;
  batch->is_clipboard = true;
  auto* obj = new (std::nothrow) VeDataObject(batch, bridge_, callbacks_, ui_thread_id_);
  if (!obj) return false;

  const HRESULT hr = OleSetClipboard(static_cast<IDataObject*>(obj));
  if (FAILED(hr)) {
    obj->Release();
    return false;
  }
  ReleaseActiveFiles();
  ReleaseActiveImage();
  ReleaseActiveText();
  active_files_obj_ = obj;
  return true;
}

bool ClipboardWin::SetImage(const std::vector<uint8_t>& png_bytes,
                            const std::vector<uint8_t>& rgba_bytes,
                            int32_t width,
                            int32_t height,
                            bool sensitive) {
  if (png_bytes.empty()) return false;
  std::vector<ClipboardBlobEntry> entries;

  const UINT cf_png = RegisterClipboardFormatW(L"PNG");
  if (cf_png != 0) {
    ClipboardBlobEntry png_entry;
    png_entry.format = static_cast<CLIPFORMAT>(cf_png);
    png_entry.bytes = png_bytes;
    entries.push_back(std::move(png_entry));
  }
  if (width > 0 && height > 0 &&
      rgba_bytes.size() >= static_cast<size_t>(width) * static_cast<size_t>(height) * 4u) {
    ClipboardBlobEntry dibv5;
    dibv5.format = CF_DIBV5;
    dibv5.bytes = BuildDibV5FromRgba(rgba_bytes.data(), width, height);
    entries.push_back(std::move(dibv5));

    ClipboardBlobEntry dib;
    dib.format = CF_DIB;
    dib.bytes = BuildLegacyDibFromRgba(rgba_bytes.data(), width, height);
    entries.push_back(std::move(dib));
  }
  if (sensitive) {
    AppendExclusionEntries(&entries);
  }

  auto* obj = new (std::nothrow) VeMemoryDataObject(std::move(entries));
  if (!obj) return false;

  const HRESULT hr = OleSetClipboard(obj);
  if (FAILED(hr)) {
    obj->Release();
    return false;
  }
  ReleaseActiveFiles();
  ReleaseActiveImage();
  ReleaseActiveText();
  active_image_obj_ = obj;
  return true;
}

bool ClipboardWin::SetSensitiveText(const std::string& utf8_text) {
  std::wstring wide = Utf8ToWide(utf8_text);
  std::vector<ClipboardBlobEntry> entries;

  ClipboardBlobEntry text_entry;
  text_entry.format = CF_UNICODETEXT;
  const size_t byte_len = (wide.size() + 1) * sizeof(wchar_t);
  text_entry.bytes.resize(byte_len);
  std::memcpy(text_entry.bytes.data(), wide.c_str(), byte_len);
  entries.push_back(std::move(text_entry));
  AppendExclusionEntries(&entries);

  auto* obj = new (std::nothrow) VeMemoryDataObject(std::move(entries));
  if (!obj) {
    if (!wide.empty()) SecureZeroMemory(&wide[0], wide.size() * sizeof(wchar_t));
    return false;
  }
  const HRESULT hr = OleSetClipboard(obj);
  if (FAILED(hr)) {
    obj->Release();
    if (!wide.empty()) SecureZeroMemory(&wide[0], wide.size() * sizeof(wchar_t));
    return false;
  }

  ReleaseActiveFiles();
  ReleaseActiveImage();
  ReleaseActiveText();
  active_text_obj_ = obj;
  active_sensitive_text_ = std::move(wide);
  active_sensitive_seq_ = GetClipboardSequenceNumber();
  return true;
}

bool ClipboardWin::ClearSensitiveText(const std::string* expected_utf8) {
  if (!active_text_obj_) return false;
  if (OleIsCurrentClipboard(active_text_obj_) != S_OK) {
    ReleaseActiveText();
    return true;  // User already replaced clipboard with something else.
  }
  if (expected_utf8 != nullptr) {
    const std::wstring expected_wide = Utf8ToWide(*expected_utf8);
    if (expected_wide != active_sensitive_text_) {
      return true;  // Clipboard holds a newer secret; leave it intact.
    }
  }
  OleSetClipboard(nullptr);
  ReleaseActiveText();
  return true;
}

bool ClipboardWin::ClearIfBatch(const std::string* batch_id,
                                const int32_t* vol_id,
                                bool clear_image) {
  bool cleared = false;
  if (active_files_obj_) {
    const auto batch = active_files_obj_->batch();
    const bool id_matches = !batch_id || (batch && batch->batch_id == *batch_id);
    const bool vol_matches = !vol_id || (batch && batch->vol_id == *vol_id);
    if (batch && id_matches && vol_matches) {
      if (OleIsCurrentClipboard(static_cast<IDataObject*>(active_files_obj_)) == S_OK &&
          SUCCEEDED(OleSetClipboard(nullptr))) {
        cleared = true;
      }
      ReleaseActiveFiles();
    }
  }
  if (clear_image && active_image_obj_) {
    if (OleIsCurrentClipboard(active_image_obj_) == S_OK &&
        SUCCEEDED(OleSetClipboard(nullptr))) {
      cleared = true;
    }
    ReleaseActiveImage();
  }
  return cleared;
}

void ClipboardWin::ClearOwnedOnShutdown() {
  if (active_files_obj_) {
    if (OleIsCurrentClipboard(static_cast<IDataObject*>(active_files_obj_)) == S_OK) {
      OleSetClipboard(nullptr);
    }
    ReleaseActiveFiles();
  }
  if (active_image_obj_) {
    if (OleIsCurrentClipboard(active_image_obj_) == S_OK) {
      OleSetClipboard(nullptr);
    }
    ReleaseActiveImage();
  }
  if (active_text_obj_) {
    if (OleIsCurrentClipboard(active_text_obj_) == S_OK) {
      OleSetClipboard(nullptr);
    }
    ReleaseActiveText();
  }
}

void ClipboardWin::OnClipboardUpdated() {
  if (active_files_obj_ != nullptr) {
    if (OleIsCurrentClipboard(static_cast<IDataObject*>(active_files_obj_)) != S_OK) {
      const std::string lost_id = active_files_obj_->batch()
          ? active_files_obj_->batch()->batch_id
          : std::string();
      ReleaseActiveFiles();
      if (!lost_id.empty() && callbacks_ != nullptr) {
        callbacks_->PostClipboardOwnershipLost(lost_id);
      }
    }
  }
  if (active_image_obj_ != nullptr && OleIsCurrentClipboard(active_image_obj_) != S_OK) {
    ReleaseActiveImage();
  }
  if (active_text_obj_ != nullptr && OleIsCurrentClipboard(active_text_obj_) != S_OK) {
    ReleaseActiveText();
  }
}

ClipboardInspectWin ClipboardWin::Inspect(HWND owner_hwnd) const {
  ClipboardInspectWin out;
  if (active_files_obj_ != nullptr &&
      OleIsCurrentClipboard(static_cast<IDataObject*>(active_files_obj_)) == S_OK) {
    out.has_files = true;
    out.is_own_files = true;
    if (active_files_obj_->batch()) {
      out.own_batch_id = active_files_obj_->batch()->batch_id;
    }
    return out;
  }

  const UINT cf_png = RegisterClipboardFormatW(L"PNG");
  if (!OpenClipboard(owner_hwnd)) return out;

  if (IsClipboardFormatAvailable(CF_HDROP)) {
    HANDLE h = GetClipboardData(CF_HDROP);
    if (h != nullptr) {
      auto* hdrop = static_cast<HDROP>(GlobalLock(h));
      if (hdrop != nullptr) {
        const UINT count = DragQueryFileW(hdrop, 0xFFFFFFFFU, nullptr, 0);
        for (UINT i = 0; i < count; ++i) {
          const UINT len = DragQueryFileW(hdrop, i, nullptr, 0);
          if (len == 0) continue;
          std::wstring buf(static_cast<size_t>(len) + 1, L'\0');
          if (DragQueryFileW(hdrop, i, &buf[0], len + 1) > 0) {
            buf.resize(len);
            out.file_paths.push_back(WideToUtf8(buf));
          }
        }
        GlobalUnlock(h);
      }
    }
    out.has_files = !out.file_paths.empty();
  }
  out.has_image =
      (cf_png != 0 && IsClipboardFormatAvailable(cf_png)) ||
      IsClipboardFormatAvailable(CF_DIBV5) ||
      IsClipboardFormatAvailable(CF_DIB);
  CloseClipboard();
  return out;
}

ClipboardImageReadWin ClipboardWin::ReadImage(HWND owner_hwnd) const {
  ClipboardImageReadWin out;
  const UINT cf_png = RegisterClipboardFormatW(L"PNG");
  if (!OpenClipboard(owner_hwnd)) return out;

  if (cf_png != 0 && IsClipboardFormatAvailable(cf_png)) {
    HANDLE h = GetClipboardData(cf_png);
    if (h != nullptr) {
      const SIZE_T sz = GlobalSize(h);
      const void* ptr = GlobalLock(h);
      if (ptr != nullptr && sz > 0) {
        out.format = "png";
        out.bytes.resize(sz);
        std::memcpy(out.bytes.data(), ptr, sz);
        out.ok = true;
      }
      if (ptr != nullptr) GlobalUnlock(h);
    }
  } else if (IsClipboardFormatAvailable(CF_DIBV5) || IsClipboardFormatAvailable(CF_DIB)) {
    const UINT fmt = IsClipboardFormatAvailable(CF_DIBV5) ? CF_DIBV5 : CF_DIB;
    HANDLE h = GetClipboardData(fmt);
    if (h != nullptr) {
      const SIZE_T sz = GlobalSize(h);
      const auto* ptr = static_cast<const uint8_t*>(GlobalLock(h));
      if (ptr != nullptr && sz >= sizeof(BITMAPINFOHEADER)) {
        BITMAPFILEHEADER bfh{};
        bfh.bfType = 0x4D42;  // "BM"
        bfh.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + sz);
        bfh.bfOffBits = ComputeDibPixelOffset(ptr, sz);
        out.format = "bmp";
        out.bytes.resize(sizeof(BITMAPFILEHEADER) + sz);
        std::memcpy(out.bytes.data(), &bfh, sizeof(BITMAPFILEHEADER));
        std::memcpy(out.bytes.data() + sizeof(BITMAPFILEHEADER), ptr, sz);
        out.ok = true;
      }
      if (ptr != nullptr) GlobalUnlock(h);
    }
  }

  CloseClipboard();
  return out;
}

}  // namespace ve_transfer
