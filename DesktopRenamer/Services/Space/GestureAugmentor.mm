#import "GestureAugmentor.h"
#include <bit>
#include <cstring>
#include <vector>
#include <map>
#include <variant>
#include <string>
#include <string_view>
#include <optional>
#include <cmath>
#include <mach/mach_time.h>

using FixedFP1616 = int32_t;

enum class IOHIDEventType : uint32_t {
  kIOHIDEventTypeVelocity = 9,
  kIOHIDEventTypeFluidTouchGesture = 23,
};

struct __attribute__((packed)) IOHIDSystemQueueElement {
  uint64_t timestamp;
  uint64_t sender_id;
  uint32_t options;
  uint32_t attribute_length;
  uint32_t event_count;
  uint8_t payload[0];
};

struct __attribute__((packed)) IOHIDEventBase {
  uint32_t size;
  IOHIDEventType type;
  uint32_t options;
  uint8_t depth;
  uint8_t reserved[3];
};

enum class IOHIDSwipeMask : uint32_t {
  kIOHIDSwipeUp = 1,
  kIOHIDSwipeDown = 2,
  kIOHIDSwipeLeft = 4,
  kIOHIDSwipeRight = 8,
};

enum class IOHIDGestureMotion : uint16_t {
  kIOHIDGestureMotionHorizontalX = 1,
  kIOHIDGestureMotionVerticalY = 2,
};

enum class IOHIDGestureFlavor : uint16_t {
  kIOHIDGestureFlavorDockPrimary = 3,
};

struct __attribute__((packed)) IOHIDFluidTouchGestureData {
  IOHIDEventBase base;
  FixedFP1616 position_x;
  FixedFP1616 position_y;
  FixedFP1616 position_z;
  IOHIDSwipeMask swipe_mask;
  IOHIDGestureMotion gesture_motion;
  IOHIDGestureFlavor gesture_flavor;
  FixedFP1616 swipe_progress;
};

struct __attribute__((packed)) IOHIDVelocityEventData {
  IOHIDEventBase base;
  FixedFP1616 velocity_x;
  FixedFP1616 velocity_y;
  FixedFP1616 velocity_z;
};

// Quartz Event fields for Dock Swipes
constexpr CGEventField kCGEventGesturePhase = static_cast<CGEventField>(132);
constexpr CGEventField kCGEventGestureSwipeMotion = static_cast<CGEventField>(123);
constexpr CGEventField kCGEventGestureSwipeProgress = static_cast<CGEventField>(124);
constexpr CGEventField kCGEventGestureSwipePositionX = static_cast<CGEventField>(125);
constexpr CGEventField kCGEventGestureSwipePositionY = static_cast<CGEventField>(126);
constexpr CGEventField kCGEventGestureSwipeVelocityX = static_cast<CGEventField>(129);
constexpr CGEventField kCGEventGestureSwipeVelocityY = static_cast<CGEventField>(130);
constexpr CGEventField kCGEventGestureSwipeMask = static_cast<CGEventField>(115);

constexpr int kGestureEnded = 4;

using CGEventDataElement = std::variant<int32_t, int64_t, float, double, std::string>;

struct CGEventData {
  int32_t version = 0;
  std::map<uint16_t, CGEventDataElement> fields;
};

namespace {

FixedFP1616 DoubleToFixedFP1616(double val) {
  const auto fixed_val = static_cast<FixedFP1616>(val * 65536.0);
  if (fixed_val == 0 && std::abs(val) > 0) {
    const FixedFP1616 sign = val > 0 ? 1 : -1;
    return sign;
  }
  return fixed_val;
}

void SwapBytes(uint8_t *ptr, size_t length) {
  for (size_t i = 0; i < length / 2; i++) {
    size_t other_index = length - i - 1;
    uint8_t temp = ptr[i];
    ptr[i] = ptr[other_index];
    ptr[other_index] = temp;
  }
}

template <typename T>
bool ReadBE(std::string_view &data, T &value) {
  constexpr size_t type_size = sizeof(T);
  if (data.size() < type_size) {
    return false;
  }
  std::memcpy(&value, data.data(), type_size);
  if constexpr (std::endian::native != std::endian::big) {
    SwapBytes(reinterpret_cast<uint8_t *>(&value), type_size);
  }
  data = data.substr(type_size);
  return true;
}

template <typename T>
void WriteBE(std::string &buffer, T value) {
  constexpr size_t type_size = sizeof(T);
  if constexpr (std::endian::native != std::endian::big) {
    SwapBytes(reinterpret_cast<uint8_t *>(&value), type_size);
  }
  buffer.append(reinterpret_cast<const char *>(&value), type_size);
}

constexpr int8_t kCGEventDataTagInt64OrBinaryBlob = 0b00;
constexpr int8_t kCGEventDataTagInt32 = 0b01;
constexpr int8_t kCGEventDataTagFloatingPoint = 0b11;

bool ReadInt64OrBinaryBlob(std::string_view &data, int16_t element_size, CGEventDataElement &result) {
  if (element_size == 1) {
    int64_t val;
    if (!ReadBE(data, val)) return false;
    result = val;
    return true;
  }
  if (element_size <= 0) return false;
  if (data.size() < static_cast<size_t>(element_size)) return false;
  result = std::string(data.data(), element_size);
  data = data.substr(element_size);
  return true;
}

bool ReadInt32(std::string_view &data, int16_t element_size, CGEventDataElement &result) {
  if (element_size == 1) {
    int32_t val;
    if (!ReadBE(data, val)) return false;
    result = val;
    return true;
  }
  return false;
}

bool ReadFloatingPoint(std::string_view &data, int16_t element_size, CGEventDataElement &result) {
  if (element_size == 1) {
    float val;
    if (!ReadBE(data, val)) return false;
    result = val;
    return true;
  }
  if (element_size == 2) {
    double val;
    if (!ReadBE(data, val)) return false;
    result = val;
    return true;
  }
  return false;
}

struct CGEventDataFieldHeader {
  uint16_t element_size = 0;
  uint16_t tag = 0;
  uint16_t field = 0;
};

bool ReadFieldHeader(std::string_view &data, CGEventDataFieldHeader &header) {
  uint16_t element_size;
  uint16_t tag_and_field;
  if (!ReadBE(data, element_size)) return false;
  if (!ReadBE(data, tag_and_field)) return false;
  header.element_size = element_size;
  header.tag = (tag_and_field >> 14) & 0x0003;
  header.field = tag_and_field & 0x3FFF;
  return true;
}

void WriteFieldHeader(std::string &buffer, const CGEventDataFieldHeader &header) {
  uint16_t tag_and_field = ((header.tag & 0x0003) << 14) | (header.field & 0x3FFF);
  WriteBE(buffer, header.element_size);
  WriteBE(buffer, tag_and_field);
}

// Helper template for std::visit overload
template<class... Ts> struct overloaded : Ts... { using Ts::operator()...; };
template<class... Ts> overloaded(Ts...) -> overloaded<Ts...>;

void WriteField(std::string &buffer, uint16_t field, const CGEventDataElement &element) {
  std::visit(
      overloaded{
          [&](int32_t value) {
            WriteFieldHeader(buffer, CGEventDataFieldHeader{
                                       .element_size = 1,
                                       .tag = kCGEventDataTagInt32,
                                       .field = field,
                                   });
            WriteBE(buffer, value);
          },
          [&](int64_t value) {
            WriteFieldHeader(buffer, CGEventDataFieldHeader{
                                       .element_size = 1,
                                       .tag = kCGEventDataTagInt64OrBinaryBlob,
                                       .field = field,
                                   });
            WriteBE(buffer, value);
          },
          [&](float value) {
            WriteFieldHeader(buffer, CGEventDataFieldHeader{
                                       .element_size = 1,
                                       .tag = kCGEventDataTagFloatingPoint,
                                       .field = field,
                                   });
            WriteBE(buffer, value);
          },
          [&](double value) {
            WriteFieldHeader(buffer, CGEventDataFieldHeader{
                                       .element_size = 2,
                                       .tag = kCGEventDataTagFloatingPoint,
                                       .field = field,
                                   });
            WriteBE(buffer, value);
          },
          [&](const std::string &value) {
            WriteFieldHeader(
                buffer, CGEventDataFieldHeader{
                          .element_size = static_cast<uint16_t>(value.size()),
                          .tag = kCGEventDataTagInt64OrBinaryBlob,
                          .field = field,
                      });
            buffer.append(value);
          }},
      element);
}

bool DeserializeCGEventData(std::string_view data, CGEventData &result) {
  if (!ReadBE(data, result.version)) return false;
  if (result.version != 2) {
    return false;
  }
  while (!data.empty()) {
    CGEventDataFieldHeader field_header;
    if (!ReadFieldHeader(data, field_header)) return false;
    CGEventDataElement element;
    switch (field_header.tag) {
      case kCGEventDataTagInt64OrBinaryBlob: {
        if (!ReadInt64OrBinaryBlob(data, field_header.element_size, element)) return false;
        result.fields[field_header.field] = element;
        break;
      }
      case kCGEventDataTagInt32: {
        if (!ReadInt32(data, field_header.element_size, element)) return false;
        result.fields[field_header.field] = element;
        break;
      }
      case kCGEventDataTagFloatingPoint: {
        if (!ReadFloatingPoint(data, field_header.element_size, element)) return false;
        result.fields[field_header.field] = element;
        break;
      }
      default:
        return false;
    }
  }
  return true;
}

std::optional<std::string> SerializeCGEventData(const CGEventData &event_data) {
  if (event_data.version != 2) {
    return std::nullopt;
  }
  std::string result;
  result.reserve(1024);
  WriteBE(result, event_data.version);
  for (const auto &[field_id, element] : event_data.fields) {
    WriteField(result, field_id, element);
  }
  return result;
}

using IOHIDEventData = std::variant<IOHIDFluidTouchGestureData, IOHIDVelocityEventData>;

struct IOHIDSystemQueueElementData {
  IOHIDSystemQueueElement header;
  std::vector<IOHIDEventData> events;
};

std::string SerializeIOHIDSystemQueueElementData(const IOHIDSystemQueueElementData &element) {
  std::string result;
  result.append(reinterpret_cast<const char *>(&element.header), sizeof(element.header));
  for (const auto &ev : element.events) {
    std::visit([&](const auto &event_data) {
      result.append(reinterpret_cast<const char *>(&event_data), sizeof(event_data));
    }, ev);
  }
  return result;
}

IOHIDSystemQueueElementData GenerateIOHIDSystemQueueElementDataFromCGEvent(CGEventRef event) {
  const int64_t phase = CGEventGetIntegerValueField(event, kCGEventGesturePhase);
  const int64_t motion = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
  const double progress = CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
  const double pos_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionX);
  const double pos_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionY);
  const double vel_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX);
  const double vel_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityY);
  const int64_t swipe_mask = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMask);

  IOHIDSystemQueueElementData result{};

  IOHIDFluidTouchGestureData fluidTouch{};
  fluidTouch.base.size = sizeof(IOHIDFluidTouchGestureData);
  fluidTouch.base.type = IOHIDEventType::kIOHIDEventTypeFluidTouchGesture;
  fluidTouch.base.options = static_cast<uint32_t>((phase & 0xFF) << 24);
  fluidTouch.base.depth = 0;
  std::memset(fluidTouch.base.reserved, 0, sizeof(fluidTouch.base.reserved));

  fluidTouch.position_x = DoubleToFixedFP1616(pos_x);
  fluidTouch.position_y = DoubleToFixedFP1616(pos_y);
  fluidTouch.position_z = 0;
  fluidTouch.swipe_mask = static_cast<IOHIDSwipeMask>(swipe_mask);
  fluidTouch.gesture_motion = static_cast<IOHIDGestureMotion>(motion);
  fluidTouch.gesture_flavor = IOHIDGestureFlavor::kIOHIDGestureFlavorDockPrimary;
  fluidTouch.swipe_progress = DoubleToFixedFP1616(progress);

  result.events.push_back(fluidTouch);

  if (vel_x != 0.0 || vel_y != 0.0 || phase == kGestureEnded) {
    IOHIDVelocityEventData velEvent{};
    velEvent.base.size = sizeof(IOHIDVelocityEventData);
    velEvent.base.type = IOHIDEventType::kIOHIDEventTypeVelocity;
    velEvent.base.options = 0;
    velEvent.base.depth = 1;
    std::memset(velEvent.base.reserved, 0, sizeof(velEvent.base.reserved));

    velEvent.velocity_x = DoubleToFixedFP1616(vel_x);
    velEvent.velocity_y = DoubleToFixedFP1616(vel_y);
    velEvent.velocity_z = 0;

    result.events.push_back(velEvent);
  }

  uint64_t timestamp = CGEventGetTimestamp(event);
  if (timestamp == 0) {
    timestamp = mach_absolute_time();
  }

  result.header.timestamp = timestamp;
  result.header.sender_id = 0;
  result.header.options = 0;
  result.header.attribute_length = 0;
  result.header.event_count = static_cast<uint32_t>(result.events.size());

  return result;
}

} // namespace

@implementation GestureAugmentor

+ (nullable CGEventRef)augmentEvent:(CGEventRef)event {
  if (!event) return nil;

  // 1. Get CFData representation of CGEvent
  CFDataRef serialized_data_ref = CGEventCreateData(nil, event);
  if (!serialized_data_ref) {
    return nil;
  }

  const uint8_t *data_ptr = CFDataGetBytePtr(serialized_data_ref);
  const CFIndex size = CFDataGetLength(serialized_data_ref);
  if (!data_ptr || size == 0) {
    CFRelease(serialized_data_ref);
    return nil;
  }

  std::string_view data(reinterpret_cast<const char *>(data_ptr), size);

  // 2. Deserialize CGEventData
  CGEventData event_data;
  if (!DeserializeCGEventData(data, event_data)) {
    CFRelease(serialized_data_ref);
    return nil;
  }
  CFRelease(serialized_data_ref);

  // 3. Generate IOHIDSystemQueueElementData
  IOHIDSystemQueueElementData element = GenerateIOHIDSystemQueueElementDataFromCGEvent(event);

  // 4. Serialize IOHIDSystemQueueElementData
  std::string serialized_io_hid_element = SerializeIOHIDSystemQueueElementData(element);

  // 5. Append serialized IOHIDSystemQueueElementData under field tag 4205
  event_data.fields[4205] = serialized_io_hid_element;

  // 6. Serialize augmented CGEventData
  std::optional<std::string> serialized_event_data = SerializeCGEventData(event_data);
  if (!serialized_event_data.has_value()) {
    return nil;
  }

  // 7. Reconstruct CGEvent from CFData
  CFDataRef augmented_data_ref = CFDataCreate(
      nil,
      reinterpret_cast<const uint8_t *>(serialized_event_data->data()),
      serialized_event_data->size());
  if (!augmented_data_ref) {
    return nil;
  }

  CGEventRef result = CGEventCreateFromData(nil, augmented_data_ref);
  CFRelease(augmented_data_ref);

  return result;
}

@end
