import MMIOVolatile

@_cdecl("main")
func main() -> CInt {
    let led = 25
    gpioInit(pin: led)
    gpioSetDirection(pin: led, out: true)
    gpioSet(pin: led, high: true)

    while true {
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

func gpioInit(pin: Int) {
    gpioSetDirection(pin: pin, out: true)
    gpioSet(pin: pin, high: false)
    gpioSetFunction(pin: pin, .SIO)
}

enum GPIOFunction: Int {
    case XIP = 0
    case SPI = 1
    case UART = 2
    case I2C = 3
    case PWM = 4
    case SIO = 5
    case PIO0 = 6
    case PIO1 = 7
    case GPCK = 8
    case USB = 9
    case NULL = 0x1f
};

// Reference to datasheet: https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf#tab-registerlist_pads_bank0
let PADS_BANK0_BASE: UInt32 = 0x4001c000
let PADS_BANK0_GPIO0_OFFSET: UInt32 = 0x00000004
let PADS_BANK0_GPIO0_BITS: UInt32 = 0x000000ff
let PADS_BANK0_GPIO0_RESET: UInt32 = 0x00000056
let PADS_BANK0_GPIO0_IE_BITS: UInt32 = 0x00000040
let PADS_BANK0_GPIO0_OD_BITS: UInt32 = 0x00000080

let IO_BANK0_BASE: UInt32 = 0x40014000
let IO_BANK0_GPIO0_CTRL_OFFSET: UInt32 = 0x00000004
let IO_BANK0_GPIO0_CTRL_FUNCSEL_LSB = 0

/// Select function for this GPIO, and ensure input/output are enabled at the pad.
/// This also clears the input/output/irq override bits.
func gpioSetFunction(pin: Int, _ function: GPIOFunction) {
    // Set input enable on, output disable off
    let padsBank = UnsafeMutablePointer<UInt32>(bitPattern: UInt(PADS_BANK0_BASE) + UInt(PADS_BANK0_GPIO0_OFFSET) + (UInt(pin) * UInt(MemoryLayout<UInt32>.stride)))!
    hwWriteMasked(
        address: padsBank, 
        values: PADS_BANK0_GPIO0_IE_BITS, 
        mask: PADS_BANK0_GPIO0_IE_BITS | PADS_BANK0_GPIO0_OD_BITS
    )
    // Zero all fields apart from fsel; we want this IO to do what the peripheral tells it.
    // This doesn't affect e.g. pullup/pulldown, as these are in pad controls.
    let controlReg = UnsafeMutablePointer<UInt32>(bitPattern: UInt(IO_BANK0_BASE) + UInt(pin * 2 * MemoryLayout<UInt32>.stride) + UInt(IO_BANK0_GPIO0_CTRL_OFFSET))!
    mmio_volatile_store_uint32_t(controlReg, UInt32(function.rawValue) << IO_BANK0_GPIO0_CTRL_FUNCSEL_LSB)
}

/// Set new values for a sub-set of the bits in a HW register.
/// 
/// Sets destination bits to values specified in \p values, if and only if corresponding bit in \p write_mask is set.
func hwWriteMasked(address: UnsafeMutablePointer<UInt32>, values: UInt32, mask writeMask: UInt32) {
    hwXORBits(address: address, mask: (address.pointee ^ values) & writeMask)
}

// Register address offsets for atomic RMW aliases
let REG_ALIAS_RW_BITS: UInt32 = 0x0000
let REG_ALIAS_XOR_BITS: UInt32 = 0x1000
let REG_ALIAS_SET_BITS: UInt32 = 0x2000
let REG_ALIAS_CLR_BITS: UInt32 = 0x3000

func hwXORBits(address: UnsafeMutablePointer<UInt32>, mask: UInt32) {
    let rawPtr = UnsafeMutableRawPointer(address).advanced(by: Int(REG_ALIAS_XOR_BITS))
    let ptr = rawPtr.assumingMemoryBound(to: UInt32.self)
    mmio_volatile_store_uint32_t(ptr, mask)
}

// SIO = the RP2040’s single-cycle I/O block.
// Reference documentation: https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf#tab-registerlist_sio
let SIO_BASE: UInt = 0xd0000000
let SIO_GPIO_OUT_SET_OFFSET: UInt = 0x00000014
let SIO_GPIO_OUT_CLR_OFFSET: UInt = 0x00000018
let SIO_GPIO_OUT_ENABLE_SET_OFFSET: UInt = 0x00000024
let SIO_GPIO_OUT_ENABLE_CLR_OFFSET: UInt = 0x00000028

func gpioSetDirection(pin: Int, out: Bool) {
    let mask: UInt32 = 1 << pin
    if out {
        gpioSetDirectionOutMasked(mask: mask)
    } else {
        gpioSetDirectionInMasked(mask: mask)
    }
}

func gpioSetDirectionOutMasked(mask: UInt32) {
    // sio_hw->gpio_oe_set = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: SIO_BASE + SIO_GPIO_OUT_ENABLE_SET_OFFSET)!
    mmio_volatile_store_uint32_t(ptr, mask)
}

func gpioSetDirectionInMasked(mask: UInt32) {
    // sio_hw->gpio_oe_clr = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: SIO_BASE + SIO_GPIO_OUT_ENABLE_CLR_OFFSET)!
    mmio_volatile_store_uint32_t(ptr, mask)
}

public func gpioSet(pin: Int, high: Bool) {
    let mask: UInt32 = 1 << pin
    if high {
        gpioSetMasked(mask: mask)
    } else {
        gpioClearMasked(mask: mask)
    }
}

func gpioSetMasked(mask: UInt32) {
    // sio_hw->gpio_set = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: SIO_BASE + SIO_GPIO_OUT_SET_OFFSET)!
    mmio_volatile_store_uint32_t(ptr, mask)
}

func gpioClearMasked(mask: UInt32) {
    // sio_hw->gpio_clr = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: SIO_BASE + SIO_GPIO_OUT_CLR_OFFSET)!
    mmio_volatile_store_uint32_t(ptr, mask)
}
