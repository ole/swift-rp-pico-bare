import RP2040

@main
struct App {
    static func main() {
        let onboardLED = 25
        gpioInit(pin: onboardLED)
        gpioSetDirection(pin: onboardLED, out: true)
        gpioSet(pin: onboardLED, high: false)

        while true {
            gpioSet(pin: onboardLED, high: true)
            sleep(milliseconds: 100)
            gpioSet(pin: onboardLED, high: false)
            sleep(milliseconds: 200)
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
