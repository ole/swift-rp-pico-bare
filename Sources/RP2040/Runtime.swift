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
