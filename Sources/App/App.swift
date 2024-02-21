import RP2040

/// crt0.S calls this immediately before main.
@_cdecl("runtime_init")
func runtimeInit() {
    // Reset all peripherals to put system into a known state,
    // - except for QSPI pads and the XIP IO bank, as this is fatal if running from flash
    // - and the PLLs, as this is fatal if clock muxing has not been reset on this boot
    // - and USB, syscfg, as this disturbs USB-to-SWD on core 1
    resetBlock(bits: ~(
            RESETS_RESET_IO_QSPI_BITS |
            RESETS_RESET_PADS_QSPI_BITS |
            RESETS_RESET_PLL_USB_BITS |
            RESETS_RESET_USBCTRL_BITS |
            RESETS_RESET_SYSCFG_BITS |
            RESETS_RESET_PLL_SYS_BITS
    ))

    // Remove reset from peripherals which are clocked only by clk_sys and
    // clk_ref. Other peripherals stay in reset until we've configured clocks.
    unresetBlockAndWait(bits: RESETS_RESET_BITS & ~(
            RESETS_RESET_ADC_BITS |
            RESETS_RESET_RTC_BITS |
            RESETS_RESET_SPI0_BITS |
            RESETS_RESET_SPI1_BITS |
            RESETS_RESET_UART0_BITS |
            RESETS_RESET_UART1_BITS |
            RESETS_RESET_USBCTRL_BITS
    ))
}

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
            delayByCounting(to: 40_000)

            // LED follows button press
            gpioSet(pin: externalLED, high: !gpioGet(pin: button))

            gpioSet(pin: onboardLED, high: false)
            delayByCounting(to: 40_000)

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
