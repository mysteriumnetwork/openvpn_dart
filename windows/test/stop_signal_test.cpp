#include <gtest/gtest.h>

#include <chrono>
#include <future>
#include <thread>

#include "stop_signal.h"

namespace openvpn_dart
{
  namespace test
  {

    namespace
    {

      using std::chrono::milliseconds;
      using std::chrono::steady_clock;

      // A wait no passing test sits out, long enough that one which does is
      // unmistakable.
      const milliseconds kLongWait(10000);

      // What counts as woken rather than timed out. Generous, so that a loaded
      // machine does not fail a test over scheduling.
      const long long kPromptMs = 5000;

      long long MillisSince(steady_clock::time_point start)
      {
        return std::chrono::duration_cast<milliseconds>(steady_clock::now() - start).count();
      }

    } // namespace

    TEST(StopSignal, WaitRunsToItsTimeoutWhenNoStopIsAskedFor)
    {
      StopSignal stop;

      EXPECT_FALSE(stop.WaitFor(milliseconds(20)));
    }

    TEST(StopSignal, RequestWakesAThreadThatIsWaiting)
    {
      StopSignal stop;
      std::promise<void> waiter_running;
      const steady_clock::time_point start = steady_clock::now();

      std::future<bool> stop_seen = std::async(
          std::launch::async,
          [&stop, &waiter_running]()
          {
            waiter_running.set_value();
            return stop.WaitFor(kLongWait);
          });

      // Let the waiter get into its wait, so that it is the wake being tested
      // and not a request that was already there when the wait began. Either
      // order has to pass.
      waiter_running.get_future().wait();
      std::this_thread::sleep_for(milliseconds(50));
      stop.Request();

      EXPECT_TRUE(stop_seen.get());
      EXPECT_LT(MillisSince(start), kPromptMs);
    }

    TEST(StopSignal, WaitReturnsAtOnceOnceAStopHasBeenAskedFor)
    {
      StopSignal stop;
      stop.Request();
      const steady_clock::time_point start = steady_clock::now();

      EXPECT_TRUE(stop.WaitFor(kLongWait));
      EXPECT_LT(MillisSince(start), kPromptMs);
    }

    TEST(StopSignal, ClearWithdrawsTheRequest)
    {
      StopSignal stop;
      stop.Request();
      stop.Clear();

      EXPECT_FALSE(stop.WaitFor(milliseconds(20)));
    }

  } // namespace test
} // namespace openvpn_dart
