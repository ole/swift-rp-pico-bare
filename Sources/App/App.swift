import RP2040

@main
struct App {
    static func main() {
        // The program must call runtimeInit before using any peripherals.
        // This should usually be the first thing you call in main().
        runtimeInit()

        let onboardLED = 25
        gpioInit(pin: onboardLED)
        gpioSetDirection(pin: onboardLED, out: true)
        gpioSet(pin: onboardLED, high: false)

        while true {
            gpioSet(pin: onboardLED, high: true)
            delayByCounting(to: 120_000)
            gpioSet(pin: onboardLED, high: false)
            delayByCounting(to: 120_000)
        }
    }
}

/// crt0.s calls this function when `main()` returns.
///
/// Most `main()` functions start an infinite loop and never return, in which
/// case `exit()` isn't needed. But it exists just in case `main()` does return.
///
/// The usual implementation is to start an infinite loop, as there is no OS to
/// return to.
///
/// - TODO: Move this into the RP2040 module if possible.
@_cdecl("exit")
func exit(_ status: CInt) {
    _exit(status)
}

/// - TODO: Move this into the RP2040 module if possible.
@_cdecl("_exit")
func _exit(_ status: CInt) {
    while true {
      // Infinite loop
    }
}

/// Artificial delay by counting in a loop.
///
/// We can delete this once we can talk to the timer peripheral.
func delayByCounting(to limit: Int32) {
    // Optimization barrier
    @inline(never)
    func increment(_ value: inout Int32) {
        value &+= 1
    }
    
    var counter: Int32 = 0
    while counter < limit {
        increment(&counter)
    }
    return
}
