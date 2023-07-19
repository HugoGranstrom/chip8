import std/[strutils, random, times, bitops, os, strformat]
import windy, opengl, sound/sound, cligen

const rows = 32
const cols = 64
#const upscale = 4

type
  Chip8Emulator* = object
    memory*: array[4096, byte]
    registers*: array[16, byte]
    counter*: uint16
    indexRegister*: uint16
    gfx*: array[rows*cols, bool]
    delayTimer*, soundTimer*: uint8
    stack*: array[16, uint16]
    stackPointer*: uint16
    key*: array[16, bool]
    drawFlag*: bool
    window*: Window
    pixelBuffer*, extraBuffer*: seq[float32]

  OpCode* = uint16

  Operation* = enum
    CallMachineCode, # 0NNN
    ClearScreen, # 00E0
    ReturnSubroutine, # 00EE
    JumpToAddr, # 1NNN
    CallSubroutine # 2NNN
    SkipNextIfEqConst # 3XNN
    SkipNextIfNotEqConst # 4XNN
    SkipNextIfEq # 5XY0
    SetConst # 6XNN
    AddConst # 7XNN
    SetTo # 8XY0
    SetOr # 8XY1
    SetAnd # 8XY2
    SetXor # 8XY3
    SetAdd # 8XY4
    SetSub # 8XY5
    SetShr # 8XY6
    SetSub2 # 8XY7
    SetShl # 8XYE
    SkipNextIfNotEq # 9XY0
    SetIndex # ANNN
    JumpToV0 # BNNN
    RandomMask # CXNN
    DrawSprite # DXYN
    SkipIfPressed # EX9E
    SkipIfNotPressed # EXA1
    GetDelay # FX07
    AwaitKey # FX0A
    SetDelay # FX15
    SetSound # FX18
    AddIndex # FX1E
    SetIndexToCharSprite # FX29
    GetBinary # FX33
    RegDump # FX55
    RegLoad # FX65
    Invalid

  RepeatingTimer* = object
    interval*, lastT*: float 

  Upscaler* = enum
    nearest, scale2x, scale4x, scale8x, scale16x

proc initRepeatingTimer*(rate: float): RepeatingTimer =
  RepeatingTimer(interval: 1 / rate, lastT: epochTime())

proc check*(timer: var RepeatingTimer): bool =
  let diff = epochTime() - timer.lastT
  if diff >= timer.interval:
    # Set lastT to next tick
    timer.lastT += timer.interval
    return true
  else:
    return false 

const chip8Fontset = [
  0xF0.byte, 0x90, 0x90, 0x90, 0xF0, # 0
  0x20, 0x60, 0x20, 0x20, 0x70, # 1
  0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
  0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
  0x90, 0x90, 0xF0, 0x10, 0x10, # 4
  0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
  0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
  0xF0, 0x10, 0x20, 0x40, 0x40, # 7
  0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
  0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
  0xF0, 0x90, 0xF0, 0x90, 0x90, # A
  0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
  0xF0, 0x80, 0x80, 0x80, 0xF0, # C
  0xE0, 0x90, 0x90, 0x90, 0xE0, # D
  0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
  0xF0, 0x80, 0xF0, 0x80, 0x80  # F
]

const hexKeys* = [
  #Key1, Key2, Key3, Key4,
  #KeyQ, KeyW, KeyE, KeyR,
  #KeyA, KeyS, KeyD, KeyF,
  #KeyZ, KeyX, KeyC, KeyV,

  KeyX, Key1, Key2, Key3,
  KeyQ, KeyW, KeyE, KeyA,
  KeyS, KeyD, KeyZ, KeyC,
  Key4, KeyR, KeyF, KeyV
]

proc initChip8*(filename: string = ""): Chip8Emulator =
  result = Chip8Emulator(
    counter: 0x200, # 512
  )

  if filename.len > 0:
    let programStr = readFile(filename)
    let program: seq[char] = @programStr
    assert program.len < 4096 - 512

    for i, x in program:
      result.memory[512 + i] = x.byte

  # load fontset
  for i, x in chip8Fontset:
    result.memory[i] = x
  # init graphics
  result.window = newWindow("Chip-8 Emulator", ivec2(64*16, 32*16))
  result.window.style = Decorated
  result.window.makeContextCurrent()
  loadExtensions()
  result.pixelBuffer = newSeq[float32](cols * rows * 16^2)
  result.extraBuffer = newSeq[float32](cols * rows * 16^2)


proc getOpCode*(emu: Chip8Emulator, index = emu.counter): OpCode =
  emu.memory[index].uint16.shl(8) or emu.memory[index+1].uint16

proc parseOperation*(opcode: OpCode): Operation =
  let first = opcode and 0xF000 # get the first 4 bits
  let last = opcode and 0x000F

  case first
  of 0x0000:
    case last
    of 0x0000:
      ClearScreen
    of 0x000E:
      ReturnSubroutine
    else:
      CallMachineCode
  of 0x1000:
    JumpToAddr
  of 0x2000:
    CallSubroutine
  of 0x3000:
    SkipNextIfEqConst
  of 0x4000:
    SkipNextIfNotEqConst
  of 0x5000:
    SkipNextIfEq
  of 0x6000:
    SetConst
  of 0x7000:
    AddConst
  of 0x8000:
    case last
    of 0x0000:
      SetTo
    of 0x0001:
      SetOr
    of 0x0002:
      SetAnd
    of 0x0003:
      SetXor
    of 0x0004:
      SetAdd
    of 0x0005:
      SetSub
    of 0x0006:
      SetShr
    of 0x0007:
      SetSub2
    of 0x000E:
      SetShl
    else:
      Invalid
  of 0x9000:
    SkipNextIfNotEq
  of 0xA000:
    SetIndex
  of 0xB000:
    JumpToV0
  of 0xC000:
    RandomMask
  of 0xD000:
    DrawSprite
  of 0xE000:
    case last
    of 0x000E:
      SkipIfPressed
    of 0x0001:
      SkipIfNotPressed
    else:
      Invalid
  of 0xF000:
    case opcode and 0x00FF:
    of 0x0007:
      GetDelay
    of 0x000A:
      AwaitKey
    of 0x0015:
      SetDelay
    of 0x0018:
      SetSound
    of 0x001E:
      AddIndex
    of 0x0029:
      SetIndexToCharSprite
    of 0x0033:
      GetBinary
    of 0x0055:
      RegDump
    of 0x0065:
      RegLoad
    else:
      Invalid
  else:
    Invalid

template currentStack*(emu: Chip8Emulator): untyped =
  emu.stack[emu.stackPointer]

template `currentStack=`*(emu: Chip8Emulator, value: uint16): untyped =
  emu.stack[emu.stackPointer] = value

template incStackPointer*(emu: Chip8Emulator) =
  emu.stackPointer += 1

template decStackPointer*(emu: Chip8Emulator) =
  if emu.stackPointer > 0:
    emu.stackPointer -= 1
  else:
    assert false, "Return at top-level detected!"

template addStack*(emu: Chip8Emulator) =
  emu.currentStack = emu.counter
  emu.incStackPointer()

template popStack*(emu: Chip8Emulator): uint16 =
  emu.decStackPointer()
  emu.currentStack


template incCounter*(emu: Chip8Emulator, amount = 2) =
  emu.counter += amount

template setCounter*(emu: Chip8Emulator, newCounter: uint16) =
  emu.counter = newCounter

proc updateKeys*(emu: var Chip8Emulator) =
  let bView = emu.window.buttonDown
  for i, key in hexKeys:
    emu.key[i] = bView[key]


proc emulateCycle*(emu: var Chip8Emulator) =
  # fetch opcode
  let opcode = emu.getOpCode()
  # decode opcode
  let first = opcode and 0xF000 # get the first 4 bits
  let second = (opcode and 0x0F00).shr(8)
  let third = (opcode and 0x00F0).shr(4)
  let last = opcode and 0x000F
  let last2 = (opcode and 0x00FF).uint8
  let rest = opcode and 0x0FFF

  let op = parseOperation(opcode)
  # execute opcode
  #print op, emu.counter#, opcode.toHex, emu.registers[0xE]
  case op
  of CallMachineCode: # 0NNN
    assert false, "Opcode 0NNN is not supported! " & opcode.toHex() 
  of ClearScreen: # 00E0
    emu.gfx = default(typeof emu.gfx) # set all pixels to zero
    emu.drawFlag = true
    emu.incCounter()
  of ReturnSubroutine: # 00EE
    emu.counter = emu.popStack() + 2
  of JumpToAddr: # 1NNN
    emu.counter = rest
  of CallSubroutine: # 2NNN
    emu.addStack()
    emu.counter = rest
  of SkipNextIfEqConst: # 3XNN
    if emu.registers[second] == last2:
      emu.incCounter()
    emu.incCounter()
  of SkipNextIfNotEqConst: # 4XNN
    if emu.registers[second] != last2:
      emu.incCounter()
    emu.incCounter()
  of SkipNextIfEq: # 5XY0
    if emu.registers[second] == emu.registers[third]:
      emu.incCounter()
    emu.incCounter()
  of SetConst: # 6XNN
    emu.registers[second] = last2
    emu.incCounter()
  of AddConst: # 7XNN
    emu.registers[second] += last2
    emu.incCounter()
  of SetTo: # 8XY0
    emu.registers[second] = emu.registers[third]
    emu.incCounter()
  of SetOr: # 8XY1
    emu.registers[second] = emu.registers[second] or emu.registers[third]
    emu.incCounter()
  of SetAnd: # 8XY2
    emu.registers[second] = emu.registers[second] and emu.registers[third]
    emu.incCounter()
  of SetXor: # 8XY3
    emu.registers[second] = emu.registers[second] xor emu.registers[third]
    emu.incCounter()
  of SetAdd: # 8XY4
    let sum = emu.registers[second].uint16 + emu.registers[third].uint16
    if sum > 255: # carry
      emu.registers[^1] = 1
      emu.registers[second] = (0x00FF and sum).uint8
    else:
      emu.registers[^1] = 0
      emu.registers[second] = sum.uint8
    emu.incCounter()
  of SetSub: # 8XY5
    emu.registers[^1] = (emu.registers[second] > emu.registers[third]).uint8
    emu.registers[second] = emu.registers[second] - emu.registers[third]
    emu.incCounter()
  of SetShr: # 8XY6
    emu.registers[^1] = 1 and emu.registers[second] # get the lowest bit
    emu.registers[second] = emu.registers[second].shr(1)
    emu.incCounter()
  of SetSub2: # 8XY7
    emu.registers[^1] = (emu.registers[second] < emu.registers[third]).uint8
    emu.registers[second] = emu.registers[third] - emu.registers[second]
    emu.incCounter()
  of SetShl: # 8XYE
    emu.registers[^1] = (0b10000000 and emu.registers[second]).shr(7) # get the highest bit
    emu.registers[second] = emu.registers[second].shl(1)
    emu.incCounter()
  of SkipNextIfNotEq: # 9XY0
    if emu.registers[second] != emu.registers[third]:
      emu.incCounter()
    emu.incCounter()
  of SetIndex: # ANNN
    emu.indexRegister = rest
    emu.incCounter()
  of JumpToV0: # BNNN
    emu.counter = emu.registers[0] + rest
  of RandomMask: # CXNN
    emu.registers[second] = rand(0..255).uint8 and last2
    emu.incCounter()
  of DrawSprite: # DXYN
    emu.drawFlag = true
    let n = last
    let x = emu.registers[second]
    let y = emu.registers[third]
    let index = cols * y + x
    emu.registers[^1] = 0
    for row in 0'u16 ..< n:
      let sprite = emu.memory[emu.indexRegister + row]
      for col in 0'u16 ..< 8'u16:
        let pixelX = (x + col) mod cols
        let pixelY = (y + row) mod rows
        let pixelIndex = cols * pixelY + pixelX
        let oldPixel = emu.gfx[pixelIndex]
        let newPixel = sprite.testBit(7 - col)
        if oldPixel and newPixel: # collision
          emu.registers[^1] = 1
        emu.gfx[pixelIndex] = oldPixel xor newPixel
    emu.incCounter()
  of SkipIfPressed: # EX9E
    if emu.key[emu.registers[second]]:
      emu.incCounter()
    emu.incCounter()
  of SkipIfNotPressed: # EXA1
    #echo emu.registers[second], " ", emu.key[emu.registers[second]]
    if not emu.key[emu.registers[second]]:
      emu.incCounter()
    emu.incCounter()
  of GetDelay: # FX07
    emu.registers[second] = emu.delayTimer
    emu.incCounter()
  of AwaitKey: # FX0A
    emu.window.title = "Chip-8 Emulator (waiting for key)"
    var waiting = true
    while waiting:
      pollEvents()
      for key in hexKeys:
        if emu.window.buttonPressed[key]:
          waiting = false
    emu.window.title = "Chip-8 Emulator"
    emu.updateKeys()
    for i, x in emu.key:
      if x:
        emu.registers[second] = i.uint8
    emu.incCounter()
  of SetDelay: # FX15
    emu.delayTimer = emu.registers[second]
    emu.incCounter()
  of SetSound: # FX18
    emu.soundTimer = emu.registers[second]
    emu.incCounter()
  of AddIndex: # FX1E
    emu.indexRegister += emu.registers[second]
    emu.incCounter()
  of SetIndexToCharSprite: # FX29
    emu.indexRegister = emu.registers[second] * 5 # 5 bytes per character
    emu.incCounter()
  of GetBinary: # FX33
    let x = emu.registers[second]
    let ones = x mod 10
    let tens = ((x - ones) mod 100) div 10
    let houndred = x div 100
    emu.memory[emu.indexRegister] = houndred
    emu.memory[emu.indexRegister+1] = tens
    emu.memory[emu.indexRegister+2] = ones
    emu.incCounter()
  of RegDump: # FX55
    for i in 0'u16 .. second:
      emu.memory[emu.indexRegister + i] = emu.registers[i]
    emu.incCounter()
  of RegLoad: # FX65
    for i in 0'u16 .. second:
      emu.registers[i] = emu.memory[emu.indexRegister + i]
    emu.incCounter()
  of Invalid:
    assert false, "Invalid opcode: " & opcode.toHex 

template toBufferIndex*(coord: IVec2, cols, upscale: int): int =
  #coord.x + cols*upscale * (rows*upscale - coord.y - 1)
  coord.x + cols * upscale * coord.y

proc scale2xInplace*[T: bool or float32](source: openArray[T], dest: var openArray[float32], rows, cols: int32) =
  for row in 0'i32 ..< rows:
      for col in 0'i32 ..< cols:
        let p = source[row * cols + col].float32
        let a = if row > 0: source[(row-1) * cols + col].float32 else: 0
        let b = if col+1 < cols: source[row * cols + (col+1)].float32 else: 0
        let c = if col > 0: source[row * cols + (col-1)].float32 else: 0
        let d = if row+1 < rows: source[(row+1) * cols + col].float32 else: 0
        var (p1, p2, p3, p4) = (p, p, p, p)

        if c == a and c != d and a != b: p1 = a
        if a == b and a != c and b != d: p2 = b
        if d == c and d != b and c != a: p3 = c
        if b == d and a != b and c != d: p4 = d
        let coord = ivec2(col, row) * 2
        for (value, vec) in [(p1, ivec2(0,0)), (p2, ivec2(1,0)), (p3, ivec2(0,1)), (p4, ivec2(1,1))]:
          let bufferIndex = toBufferIndex(coord + vec, cols, 2)
          dest[bufferIndex] = value

proc performScale2x*[T: bool or float32](source: openArray[T], rows, cols: int32): seq[float32] =
  result = newSeq[float32](rows * cols * 2^2)
  scale2xInplace(source, result, rows, cols)

proc draw*(emu: var Chip8Emulator, upscaler: Upscaler) =
  glClear(GL_COLOR_BUFFER_BIT)

  var scaleFactor: int32
  # transfer gfx to pixel buffer and upscale
  case upscaler
  of nearest:
    scaleFactor = 1
    for row in 0'i32 ..< rows:
      for col in 0'i32 ..< cols:
        let pixelValue = emu.gfx[row * cols + col].float32
        let coord = ivec2(col, row)
        let bufferIndex = toBufferIndex(coord, cols, 1)
        emu.pixelBuffer[bufferIndex] = pixelValue

  of scale2x:
    scaleFactor = 2
    scale2xInplace(emu.gfx, emu.pixelBuffer, rows, cols)

  of scale4x:
    scaleFactor = 4
    #let buffer2x = performScale2x(emu.gfx, rows, cols)
    scale2xInplace(emu.gfx, emu.extraBuffer, rows, cols)
    scale2xInplace(emu.extraBuffer, emu.pixelBuffer, 2*rows, 2*cols)
  
  of scale8x:
    scaleFactor = 8
    let buffer2x = performScale2x(emu.gfx, rows, cols)
    scale2xInplace(buffer2x, emu.extraBuffer, 2*rows, 2*cols)
    scale2xInplace(emu.extraBuffer, emu.pixelBuffer, 4*rows, 4*cols)
  
  of scale16x:
    scaleFactor = 16
    #let buffer4x = performScale2x(emu.gfx, rows, cols).performScale2x(2*rows, 2*cols).performScale2x(4*rows, 4*cols)
    scale2xInplace(emu.gfx, emu.extraBuffer, rows, cols)
    scale2xInplace(emu.extraBuffer, emu.pixelBuffer, 2*rows, 2*cols)
    scale2xInplace(emu.pixelBuffer, emu.extraBuffer, 4*rows, 4*cols)
    scale2xInplace(emu.extraBuffer, emu.pixelBuffer, 8*rows, 8*cols)
    #scale2xInplace(buffer4x, emu.pixelBuffer, 8*rows, 8*cols)

  glRasterPos2f(-1, 1)
  glPixelZoom(16 / scaleFactor, -16 / scaleFactor)
  glDrawPixels(cols*scaleFactor, rows*scaleFactor, GL_LUMINANCE, cGL_FLOAT, cast[pointer](emu.pixelBuffer[0].addr))
  emu.window.swapBuffers()

proc run*(emu: var Chip8Emulator, framerate = 60.0, processingRate = 1000.0, upscaler = nearest) =
  var upscaler = upscaler
  var internalClock = initRepeatingTimer(60) # 60Hz
  var graphicsClock = initRepeatingTimer(framerate) # 60 FPS
  var secondClock = initRepeatingTimer(1)
  emu.draw(upscaler) # first draw
  let cycle = 10 # the number of ops in a cycle
  var snd = newSoundWithPath("buzz.ogg")
  var isSounding = false
  while not emu.window.closeRequested:
    let tStart = epochTime()
    for i in 0 ..< cycle:
      pollEvents()
      emu.updateKeys()
      emu.emulateCycle()

      # Draw only when the screen has changed
      if emu.drawFlag and graphicsClock.check:
        emu.draw(upscaler)
        emu.drawFlag = false

      if internalClock.check:
        # update timers
        if emu.delayTimer > 0:
          emu.delayTimer -= 1
        if emu.soundTimer > 0:
          if not isSounding:
            snd.play()
          emu.soundTimer -= 1
        elif emu.soundTimer == 0 and isSounding:
          snd.stop()
          isSounding = false
      
      if emu.window.buttonPressed[KeySpace]:
        if upscaler == Upscaler.high:
          upscaler = Upscaler.low
        else:
          upscaler.inc
        echo "Switched upscaler to: ", upscaler

    let dur = epochTime() - tStart
    if secondClock.check:
      echo "FPS: ", (cycle.float / dur).int
    let slack = cycle.float / processingRate - dur
    if slack > 0:
      sleep(int(slack * 1000))

proc emulator(filename: string, fps: float = 60, rate: float = 500, upscaling: Upscaler = nearest) =
  ## A Chip-8 emulator written in Nim.
  ## Use keys 1234 - zxcv.
  ## Press <Space> to cycle through upscaling methods.
  var emu = initChip8(filename)
  emu.run(fps, rate, upscaling)

when isMainModule:
  dispatch emulator, help = {"filename": "The path to the ROM", "fps": "The graphics framerate", "rate": "The number of operations to run per second", "upscaling": "The upscaling method to use: nearest, scale2x, scale4x, scale8x, scale16x"}