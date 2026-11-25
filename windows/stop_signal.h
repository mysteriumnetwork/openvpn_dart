#ifndef FLUTTER_PLUGIN_OPENVPN_DART_STOP_SIGNAL_H_
#define FLUTTER_PLUGIN_OPENVPN_DART_STOP_SIGNAL_H_

#include <chrono>
#include <condition_variable>
#include <mutex>

namespace openvpn_dart
{

    // A request to stop that a thread can sleep on.
    //
    // A thread that polls -- look, sleep a second, look again -- cannot be
    // joined before its sleep ends, and whoever joins it waits that out.
    // Sleeping in WaitFor() instead, it is woken by Request() and can be
    // joined at once.
    class StopSignal
    {
    public:
        // Asks for a stop and wakes whoever is in WaitFor().
        void Request()
        {
            {
                // Under the lock, or the request could land between a waiter
                // finding none and going to sleep, and be slept through.
                std::lock_guard<std::mutex> lock(mutex_);
                requested_ = true;
            }
            changed_.notify_all();
        }

        // Withdraws the request, ready for the next thread to wait on this.
        void Clear()
        {
            std::lock_guard<std::mutex> lock(mutex_);
            requested_ = false;
        }

        // Sleeps until a stop is asked for or |timeout| has passed, whichever
        // comes first. Returns whether a stop has been asked for.
        bool WaitFor(std::chrono::milliseconds timeout)
        {
            std::unique_lock<std::mutex> lock(mutex_);
            return changed_.wait_for(lock, timeout, [this]
                                     { return requested_; });
        }

    private:
        std::mutex mutex_;
        std::condition_variable changed_;
        bool requested_ = false;
    };

} // namespace openvpn_dart

#endif // FLUTTER_PLUGIN_OPENVPN_DART_STOP_SIGNAL_H_
