# chip8
A Chip-8 emulator written in Nim.

After having built a simple CPU in the game [Turing Comeplete](https://turingcomplete.game/), I got inspired to make an emulator as well.
And Chip-8 seems to be the goto first emulator, so here it is. It has quite a few rough edges, but all opcodes (except `0NNN`) are implemented.

## Features
- Upscaling: Nearest neighbor, Scale2x, Scale4x, Scale8x, Scale16x (press `<Space>` when running to cycle through them)
- Adjustable framerate and cpu processing rate
- Keyboard controls
- Sound

## Libraries used
- Graphics and input: [windy](https://github.com/treeform/windy) & [OpenGL](https://github.com/nim-lang/opengl)
- Sound: [sound](https://github.com/yglukhov/sound/)
- CLI interface: [cligen](https://github.com/c-blake/cligen)

## Usage
1. Clone this repo.
2. Install dependencies: `nimble install -d`.
3. Drop your own `buzz.ogg` in the folder.
4. Build the emulator: `nim c -d:release emulator.nim`
5. Run ROM: `./emulator --filename path/to/rom`
```
Usage:
  emulator [REQUIRED,optional-params] 
A Chip-8 emulator written in Nim. Use keys 1234 - zxcv.  Press <Space> to cycle through upscaling methods.
Options:
  -h, --help                             print this cligen-erated help
  --help-syntax                          advanced: prepend,plurals,..
  -f=, --filename=   string    REQUIRED  The path to the ROM
  --fps=             float     60.0      The graphics framerate
  -r=, --rate=       float     500.0     The number of operations to run per second
  -u=, --upscaling=  Upscaler  nearest   The upscaling method to use: nearest, scale2x, scale4x, scale8x, scale16x
```

## Notes
- The sound is a bit sluggish.
- Flickering screen (but that seems to be normal among Chip-8 emulators due to the XOR nature of the sprite drawing).
- The higher upscaling options (Scale8x, Scale16x) looks quite weird most often, but it is fun to play around with non the less.


## References
My main two sources during the writing of the emulator was [Cowgod's Chip-8 Technical Reference](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM) and [Laurence Muller's tutorial](https://multigesture.net/articles/how-to-write-an-emulator-chip-8-interpreter/).
