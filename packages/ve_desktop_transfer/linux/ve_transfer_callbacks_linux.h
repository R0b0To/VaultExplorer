#ifndef VE_DESKTOP_TRANSFER_CALLBACKS_LINUX_H_
#define VE_DESKTOP_TRANSFER_CALLBACKS_LINUX_H_

#include <cstdint>
#include <string>
#include <vector>

namespace ve_transfer {

class TransferCallbacksLinux {
 public:
  virtual ~TransferCallbacksLinux() = default;

  virtual void EmitDropEvent(int64_t view_id,
                             const char* method_name,
                             double x,
                             double y,
                             const std::vector<std::string>& paths) = 0;

  virtual void EmitBatchRealized(const std::string& batch_id,
                                 const std::vector<std::string>& paths) = 0;

  virtual void EmitBatchTransferFinished(const std::string& batch_id,
                                         bool success,
                                         bool immediate_if_unused) = 0;

  virtual void EmitClipboardOwnershipLost(const std::string& batch_id) = 0;
};

}  // namespace ve_transfer

#endif  // VE_DESKTOP_TRANSFER_CALLBACKS_LINUX_H_
