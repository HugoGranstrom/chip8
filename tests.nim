import std / [unittest]
import ./emulator

test "Opcodes":
  let l = [
    (0x0111.OpCode, CallMachineCode),
    (0x00E0, ClearScreen),
    (0x00EE, ReturnSubroutine),
    (0x1AAA, JumpToAddr),
    (0x2BBB, CallSubroutine),
    (0x34AB, SkipNextIfEqConst),
    (0x44AB, SkipNextIfNotEqConst),
    (0x5AB0, SkipNextIfEq),
    (0x6ABC, SetConst),
    (0x7ABC, AddConst),
    (0x8AB0, SetTo),
    (0x8AB1, SetOr),
    (0x8AB2, SetAnd),
    (0x8AB3, SetXor),
    (0x8AB4, SetAdd),
    (0x8AB5, SetSub),
    (0x8AB6, SetShr),
    (0x8AB7, SetSub2),
    (0x8ABE, SetShl),
    (0x8AB8, Invalid),
    (0x9AB0, SkipNextIfNotEq),
    (0xA111, SetIndex),
    (0xB222, JumpToV0),
    (0xC3AA, RandomMask),
    (0xD123, DrawSprite),
    (0xE19E, SkipIfPressed),
    (0xE2A1, SkipIfNotPressed),
    (0xF107, GetDelay),
    (0xF20A, AwaitKey),
    (0xF315, SetDelay),
    (0xF418, SetSound),
    (0xF41E, AddIndex),
    (0xF429, SetIndexToCharSprite),
    (0xF433, GetBinary),
    (0xF455, RegDump),
    (0xF465, RegLoad),
  ]

  # check coverage
  for o in Operation:
    var found = false
    for (_, oo) in l:
      if o == oo: found = true
    assert found, "Test doesn't cover opcode: " & $o

  for (opcode, o) in l:
    check parseOperation(opcode) == o