//
//  UltimateLockFreeRingBuffer.hpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Ultra-high performance SPSC Lock-Free RingBuffer with Cache-Line Alignment.
//

#ifndef UltimateLockFreeRingBuffer_hpp
#define UltimateLockFreeRingBuffer_hpp

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <new>

namespace VLCUltimateEngine {

/// SPSC (Single-Producer Single-Consumer) Lock-Free RingBuffer for Float32 audio streams.
/// Guarantees Zero Allocations, Zero Locks, and No False-Sharing across CPU cores.
class UltimateLockFreeRingBuffer {
public:
    /// Constructs a ring buffer with power-of-two capacity.
    /// @param min_capacity Minimum required capacity in elements. Will be rounded up to power of 2.
    explicit UltimateLockFreeRingBuffer(size_t min_capacity)
        : capacity_(next_power_of_two(min_capacity < 128 ? 128 : min_capacity)),
          mask_(capacity_ - 1),
          buffer_(nullptr)
    {
        // Allocate buffer aligned to 64 bytes (L1 cache line boundary)
        size_t bytes = capacity_ * sizeof(float);
        void* raw_ptr = nullptr;
        if (posix_memalign(&raw_ptr, 64, bytes) == 0) {
            buffer_ = static_cast<float*>(raw_ptr);
            std::memset(buffer_, 0, bytes);
        } else {
            // Fallback standard allocation
            buffer_ = new float[capacity_]();
        }
        
        write_index_.store(0, std::memory_order_relaxed);
        read_index_.store(0, std::memory_order_relaxed);
    }

    ~UltimateLockFreeRingBuffer() {
        if (buffer_ != nullptr) {
            std::free(buffer_);
            buffer_ = nullptr;
        }
    }

    // Non-copyable, non-movable to guarantee address stability for real-time threads
    UltimateLockFreeRingBuffer(const UltimateLockFreeRingBuffer&) = delete;
    UltimateLockFreeRingBuffer& operator=(const UltimateLockFreeRingBuffer&) = delete;
    UltimateLockFreeRingBuffer(UltimateLockFreeRingBuffer&&) = delete;
    UltimateLockFreeRingBuffer& operator=(UltimateLockFreeRingBuffer&&) = delete;

    /// Writes data to the ring buffer. Called EXCLUSIVELY by the Producer thread.
    /// Zero-allocation, lock-free.
    /// @param data Pointer to input float samples.
    /// @param count Number of samples to write.
    /// @return Number of samples actually written.
    size_t write(const float* data, size_t count) noexcept {
        if (data == nullptr || count == 0 || buffer_ == nullptr) {
            return 0;
        }

        const size_t current_write = write_index_.load(std::memory_order_relaxed);
        const size_t current_read  = read_index_.load(std::memory_order_acquire);

        const size_t occupied = current_write - current_read;
        const size_t available = capacity_ - occupied;
        const size_t to_write = std::min(count, available);

        if (to_write == 0) {
            return 0;
        }

        const size_t write_offset = current_write & mask_;
        const size_t first_chunk = std::min(to_write, capacity_ - write_offset);
        const size_t second_chunk = to_write - first_chunk;

        std::memcpy(buffer_ + write_offset, data, first_chunk * sizeof(float));
        if (second_chunk > 0) {
            std::memcpy(buffer_, data + first_chunk, second_chunk * sizeof(float));
        }

        write_index_.store(current_write + to_write, std::memory_order_release);
        return to_write;
    }

    /// Reads data from the ring buffer. Called EXCLUSIVELY by the Consumer thread.
    /// Zero-allocation, lock-free.
    /// @param destination Pointer to output float buffer.
    /// @param count Number of samples to read.
    /// @return Number of samples actually read.
    size_t read(float* destination, size_t count) noexcept {
        if (destination == nullptr || count == 0 || buffer_ == nullptr) {
            return 0;
        }

        const size_t current_read  = read_index_.load(std::memory_order_relaxed);
        const size_t current_write = write_index_.load(std::memory_order_acquire);

        const size_t available = current_write - current_read;
        const size_t to_read = std::min(count, available);

        if (to_read == 0) {
            return 0;
        }

        const size_t read_offset = current_read & mask_;
        const size_t first_chunk = std::min(to_read, capacity_ - read_offset);
        const size_t second_chunk = to_read - first_chunk;

        std::memcpy(destination, buffer_ + read_offset, first_chunk * sizeof(float));
        if (second_chunk > 0) {
            std::memcpy(destination + first_chunk, buffer_, second_chunk * sizeof(float));
        }

        read_index_.store(current_read + to_read, std::memory_order_release);
        return to_read;
    }

    /// Returns readable elements available. Safe for either thread.
    size_t available_read() const noexcept {
        const size_t r = read_index_.load(std::memory_order_acquire);
        const size_t w = write_index_.load(std::memory_order_acquire);
        return (w >= r) ? (w - r) : 0;
    }

    /// Returns writable space available. Safe for either thread.
    size_t available_write() const noexcept {
        const size_t r = read_index_.load(std::memory_order_acquire);
        const size_t w = write_index_.load(std::memory_order_acquire);
        const size_t occupied = (w >= r) ? (w - r) : 0;
        return (occupied < capacity_) ? (capacity_ - occupied) : 0;
    }

    /// Resets the buffer state. Must only be invoked when both producer and consumer are quiescent.
    void reset() noexcept {
        write_index_.store(0, std::memory_order_release);
        read_index_.store(0, std::memory_order_release);
    }

    /// Returns total buffer capacity in elements.
    size_t capacity() const noexcept {
        return capacity_;
    }

private:
    static constexpr size_t next_power_of_two(size_t val) noexcept {
        size_t p = 1;
        while (p < val) {
            p <<= 1;
        }
        return p;
    }

    const size_t capacity_;
    const size_t mask_;
    float* buffer_;

    // 64-byte alignment guarantees write_index_ and read_index_ inhabit distinct L1 cache lines.
    // This strictly eliminates cache-coherency ping-pong and False Sharing between audio threads.
    alignas(64) std::atomic<size_t> write_index_{0};
    alignas(64) std::atomic<size_t> read_index_{0};
};

} // namespace VLCUltimateEngine

#endif /* UltimateLockFreeRingBuffer_hpp */
