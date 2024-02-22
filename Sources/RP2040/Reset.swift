public let RESETS_BASE: UInt32 = 0x4000c000
public let RESETS_RESET_OFFSET: UInt32 = 0x00000000
public let RESETS_RESET_DONE_OFFSET: UInt32 = 0x00000008
public let RESETS_RESET_BITS: UInt32 = 0x01ffffff
public let RESETS_RESET_ADC_BITS: UInt32 = 0x00000001
public let RESETS_RESET_IO_QSPI_BITS: UInt32 = 0x00000040
public let RESETS_RESET_PADS_QSPI_BITS: UInt32 = 0x00000200
public let RESETS_RESET_PLL_SYS_BITS: UInt32 = 0x00001000
public let RESETS_RESET_PLL_USB_BITS: UInt32 = 0x00002000
public let RESETS_RESET_RTC_BITS: UInt32 = 0x00008000
public let RESETS_RESET_SPI0_BITS: UInt32 = 0x00010000
public let RESETS_RESET_SPI1_BITS: UInt32 = 0x00020000
public let RESETS_RESET_SYSCFG_BITS: UInt32 = 0x00040000
public let RESETS_RESET_UART0_BITS: UInt32 = 0x00400000
public let RESETS_RESET_UART1_BITS: UInt32 = 0x00800000
public let RESETS_RESET_USBCTRL_BITS: UInt32 = 0x01000000

/// Reset the specified HW blocks
public func resetBlock(bits: UInt32) {
    let resets = UnsafeMutablePointer<UInt32>(bitPattern: UInt(RESETS_BASE + RESETS_RESET_OFFSET))!
    hwSetBits(address: resets, mask: bits)
}

/// Bring the specified HW blocks out of reset
public func unresetBlock(bits: UInt32) {
    let resets = UnsafeMutablePointer<UInt32>(bitPattern: UInt(RESETS_BASE + RESETS_RESET_OFFSET))!
    hwClearBits(address: resets, mask: bits)
}

/// Bring the specified HW blocks out of reset and wait for completion
public func unresetBlockAndWait(bits: UInt32) {
    unresetBlock(bits: bits)
    let resetDone = UnsafeMutablePointer<UInt32>(bitPattern: UInt(RESETS_BASE + RESETS_RESET_DONE_OFFSET))!
    while true {
        let isResetDone = ~mmio_volatile_load_uint32_t(resetDone) & bits == 0
        if isResetDone {
            break
        }
    }
}
