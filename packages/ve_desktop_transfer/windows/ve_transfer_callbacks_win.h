#ifndef VE_DESKTOP_TRANSFER_CALLBACKS_WIN_H_
#define VE_DESKTOP_TRANSFER_CALLBACKS_WIN_H_

#include <cstdint>
#include <string>
#include <vector>

namespace ve_transfer {

class TransferCallbacksWin {
 public:
  virtual ~TransferCallbacksWin() = default;

  virtual void PostDropEvent(int64_t view_id,
                             const char* method_name,
                             double x,
                             double y,
                             std::vector<std::string> paths) = 0;

  virtual void PostBatchRealized(std::string batch_id,
                                 std::vector<std::string> paths) = 0;

  virtual void PostBatchTransferFinished(std::string batch_id,
                                         bool success,
                                         bool immediate_if_unused) = 0;

  virtual void PostClipboardOwnershipLost(std::string batch_id) = 0;
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_CALLBACKS_WIN_H_
