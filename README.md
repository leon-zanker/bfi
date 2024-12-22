# bfi

`bfi` is a Brainfuck interpreter intended for use with stdin and stdout.

## Usage

- Specify the input for the brainfuck program through stdin (pipe into the process or otherwise read from the terminal)
- Specify the program to run as the first argument
- Output goes to stdout

Examples (Unix):

```shell
# This will write 'hello, world' to stdout, outputting it to the terminal
echo "hello, world" | bfi ",[.,]"
```

```shell
# This will read the program from a file and write its output to stdout
bfi "$(cat my_file.bf)"
```

```shell
# This will enter an infinite loop, reading your input from the terminal and appending everything to a file each time
bfi ",[.,]" >> my_file.txt
```

Examples (Windows):

```powershell
# This will write 'hello, world' to stdout, outputting it to the terminal
echo "hello, world" | bfi ",[.,]"
```

```powershell
# This will read the program from a file and write its output to stdout
bfi (Get-Content my_file.bf -Raw)
```

```powershell
# This will enter an infinite loop, reading your input from the terminal and appending everything to a file each time
bfi ",[.,]" >> my_file.txt
```

Try the examples in the `examples` folder as well!

## Specifications

- Supported operators:
	- '>': move pointer location right
	- '<': move pointer location left
	- '+': increment cell value at pointer location
	- '-': decrement cell value at pointer location
	- '[': start loop
	- ']': end loop
	- ',': read byte from input into cell value at pointer location
	- '.': write cell value at pointer location to output
- Tape expands to positive infinity
- Pointer starts at location 0
- Negative pointer location causes a runtime error
- Cell values are unsigned 8-bit integers
- Cell values default to 0
- Cell values wrap to 255 when below zero and to 0 when above 255
- Reading from empty input will set the cell value at the current pointer location to 0
- Nested loops are supported
- All non-operator characters from program are ignored (no comment syntax)

## Installation

This guide expects the `zig` executable to be in your PATH.

```shell
git clone 'github.com/leon-zanker/bfi.git'
cd bfi
zig build -Doptimize=ReleaseSafe
# Add the resulting executable zig-out/bin/bfi or zig-out/bin/bfi.exe on Windows to your PATH
```

## As a Library

The interpreter is written in pure Zig without third party dependencies and features a generic `execute()` function that lets you specify any reader with a `fn readByte(self: @This()) anyerror!u8` method and any writer with a `fn writeByte(self: @This(), byte: u8) anyerror!void` method.

See the tests in the `Interpreter.zig` file and the usage in the `main.zig` file for examples on how to use different readers and writers with the interpreter.

See the import in `main.zig` for how to import and use the interpreter in your code.
