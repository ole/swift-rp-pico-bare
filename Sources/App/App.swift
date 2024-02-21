import RP2040

@main
struct App {
    static func main() {
        let onboardLED = 25
        gpioInit(pin: onboardLED)
        gpioSetDirection(pin: onboardLED, out: true)
        gpioSet(pin: onboardLED, high: false)

        let externalLED = 17
        gpioInit(pin: externalLED)
        gpioSetDirection(pin: externalLED, out: true)
        gpioSet(pin: externalLED, high: false)

        let button = 16
        gpioInit(pin: button)
        gpioSetDirection(pin: button, out: false)
        gpioPullUp(pin: button)

        while true {
            // Blink
            gpioSet(pin: onboardLED, high: true)
            delayByCounting(to: 30_000)

            // LED follows button press
            gpioSet(pin: externalLED, high: !gpioGet(pin: button))

            gpioSet(pin: onboardLED, high: false)
            delayByCounting(to: 120_000)

            gpioSet(pin: externalLED, high: !gpioGet(pin: button))
        }
    }
}

@_cdecl("exit")
func exit(_ status: CInt) {
    _exit(status)
}

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
