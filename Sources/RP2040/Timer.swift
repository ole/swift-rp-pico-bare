import MMIOVolatile

let TIMER_BASE: UInt32 = 0x40054000
/// Write to bits 63:32 of time
let TIMER_TIMEHW_OFFSET: UInt32 = 0x00000000
/// Write to bits 31:0 of time
let TIMER_TIMELW_OFFSET: UInt32 = 0x00000004
/// Read from bits 63:32 of time
let TIMER_TIMEHR_OFFSET: UInt32 = 0x00000008
/// Read from bits 31:0 of time
let TIMER_TIMELR_OFFSET: UInt32 = 0x0000000c
/// Raw read from bits 63:32 of time (no side effects)
let TIMER_TIMERAWH_OFFSET: UInt32 = 0x00000024
/// Raw read from bits 31:0 of time (no side effects)
let TIMER_TIMERAWL_OFFSET: UInt32 = 0x00000028

public func sleep(milliseconds delay: Int64) {
    sleep(microseconds: delay * 1000)
}

public func sleep(microseconds delay: Int64) {
    guard let delay = UInt64(exactly: delay) else {
        return
    }
    busyWait(microseconds: delay)
}

/// Returns the current timer value (microseconds since boot).
public func currentTime() -> UInt64 {
    // Need to make sure that the upper 32 bits of the timer
    // don't change, so read that first
    let timeRawH = UnsafePointer<UInt32>(bitPattern: UInt(TIMER_BASE) + UInt(TIMER_TIMERAWH_OFFSET))!
    let timeRawL = UnsafePointer<UInt32>(bitPattern: UInt(TIMER_BASE) + UInt(TIMER_TIMERAWL_OFFSET))!
    var hi: UInt32 = mmio_volatile_load_uint32_t(timeRawH)
    var lo: UInt32
    repeat {
        // Read the lower 32 bits
        lo = mmio_volatile_load_uint32_t(timeRawL)
        // Now read the upper 32 bits again and
        // check that it hasn't incremented. If it has loop around
        // and read the lower 32 bits again to get an accurate value
        let nextHi = mmio_volatile_load_uint32_t(timeRawH)
        if hi == nextHi {
            break
        }
        hi = nextHi
    } while true
    return (UInt64(hi) << 32) | UInt64(lo)
}

func busyWait(microseconds delay: UInt64) {
    let base = currentTime()
    let target = base + delay
    guard target > base else {
        return
    }
    while currentTime() < target {
        // Spin
    }
}
