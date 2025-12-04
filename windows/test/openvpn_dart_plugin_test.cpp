#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "openvpn_dart_plugin.h"

namespace openvpn_dart
{
  namespace test
  {

    namespace
    {

      using flutter::EncodableMap;
      using flutter::EncodableValue;
      using flutter::MethodCall;
      using flutter::MethodResultFunctions;

    } // namespace

    TEST(OpenVpnDartPlugin, GetStatus)
    {
      OpenVpnDartPlugin plugin(nullptr);
      // Save the reply value from the success callback.
      std::string result_string;
      plugin.HandleMethodCall(
          MethodCall("status", std::make_unique<EncodableValue>()),
          std::make_unique<MethodResultFunctions<>>(
              [&result_string](const EncodableValue *result)
              {
                result_string = std::get<std::string>(*result);
              },
              nullptr, nullptr));

      // Should return initial status
      EXPECT_EQ(result_string, "disconnected");
    }

  } // namespace test
} // namespace openvpn_dart
