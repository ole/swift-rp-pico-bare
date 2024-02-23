/// Performs the default initialization after boot. Brings the RP2040
/// peripherals out of reset and initializes the clocks, incl. ramping up
/// the CPU clock speed to full.
///
/// The program must call this before using any peripherals. This should
/// usually be the first function you call in `main()`.
///
/// - Note: The Raspberry Pi Pico C SDK defines a function called `runtime_init`
///   and calls it automatically just before calling `main()`. We decided to
///   make this call an explicit step for transparency into the boot process.
public func runtimeInit() { 
    // Reset all peripherals to put system into a known state,
    // - except for QSPI pads and the XIP IO bank, as this is fatal if running from flash
    // - and the PLLs, as this is fatal if clock muxing has not been reset on this boot
    // - and USB, syscfg, as this disturbs USB-to-SWD on core 1
    //
    // Disables all peripherals except the ones listed in the bitmask.
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
    //
    // Enables all peripherals except the ones listed in the bitmask.
    // I.e. the peripherals listed here are the ones that
    // "stay in reset until we've configured clocks".
    unresetBlockAndWait(bits: RESETS_RESET_BITS & ~(
            RESETS_RESET_ADC_BITS |
            RESETS_RESET_RTC_BITS |
            RESETS_RESET_SPI0_BITS |
            RESETS_RESET_SPI1_BITS |
            RESETS_RESET_UART0_BITS |
            RESETS_RESET_UART1_BITS |
            RESETS_RESET_USBCTRL_BITS
    ))

    // Status at this point:
    // - ADC, RTC, SPI0, SPI1, UART0, UART1 are in reset (= disabled)
    // - The reset status of USBCTRL is unchanged
    // - All other peripherals are out of reset (= enabled)
}
