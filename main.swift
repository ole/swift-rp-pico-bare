@_cdecl("main")
func main() -> CInt {
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
