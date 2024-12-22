// MIT License

// Copyright (c) 2024 Leon Zanker

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const Interpreter = @This();

const std = @import("std");
const mem = std.mem;
const math = std.math;

const Lexer = struct {
    pub const Token = enum {
        inc_ptr,
        dec_ptr,
        inc_val,
        dec_val,
        loop_start,
        loop_end,
        input,
        output,
    };

    const LoopMap = struct {
        allocator: mem.Allocator,

        starts: std.AutoHashMap(usize, usize),
        ends: std.AutoHashMap(usize, usize),

        pub fn init(allocator: mem.Allocator) LoopMap {
            return .{
                .allocator = allocator,
                .starts = std.AutoHashMap(usize, usize).init(allocator),
                .ends = std.AutoHashMap(usize, usize).init(allocator),
            };
        }

        pub fn deinit(self: *LoopMap) void {
            self.starts.deinit();
            self.ends.deinit();
        }

        pub fn build(self: *LoopMap, tokens: []const Token) !void {
            var stack = std.ArrayList(usize).init(self.allocator);
            defer stack.deinit();
            for (tokens, 0..) |token, i| {
                switch (token) {
                    .loop_start => try stack.append(i),
                    .loop_end => {
                        const start = stack.popOrNull() orelse return error.UnmatchedLoopEnd;
                        try self.starts.put(start, i);
                        try self.ends.put(i, start);
                    },
                    else => {},
                }
            }
            if (stack.items.len > 0) return error.UnmatchedLoopStart;
        }
    };

    tokens: std.ArrayList(Token),
    loop_map: LoopMap,

    pub fn init(allocator: mem.Allocator) Lexer {
        return .{
            .tokens = std.ArrayList(Token).init(allocator),
            .loop_map = LoopMap.init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
        self.loop_map.deinit();
    }

    pub fn tokenize(self: *Lexer, code: []const u8) !void {
        var i: usize = 0;
        while (i < code.len) : (i += 1) {
            switch (code[i]) {
                '>' => try self.tokens.append(.inc_ptr),
                '<' => try self.tokens.append(.dec_ptr),
                '+' => try self.tokens.append(.inc_val),
                '-' => try self.tokens.append(.dec_val),
                '[' => try self.tokens.append(.loop_start),
                ']' => try self.tokens.append(.loop_end),
                ',' => try self.tokens.append(.input),
                '.' => try self.tokens.append(.output),
                else => {},
            }
        }
        if (self.tokens.items.len == 0) return error.NoValidTokens;
        try self.loop_map.build(self.tokens.items);
    }

    pub fn getTokens(self: Lexer) []const Token {
        return self.tokens.items;
    }

    pub fn getConsecutiveTokens(self: Lexer, start_index: usize) usize {
        const needle = self.tokens.items[start_index];
        var count: usize = 1;
        while (start_index + count < self.tokens.items.len and
            self.tokens.items[start_index + count] == needle) : (count += 1)
        {}
        return count;
    }

    pub fn loopEndFromLoopStart(self: Lexer, loop_start_index: usize) usize {
        return self.loop_map.starts.get(loop_start_index).?;
    }

    pub fn loopStartFromLoopEnd(self: Lexer, loop_end_index: usize) usize {
        return self.loop_map.ends.get(loop_end_index).?;
    }
};

allocator: mem.Allocator,

tape: std.ArrayList(u8),
dptr: usize = 0,

pub fn init(allocator: mem.Allocator) Interpreter {
    return .{
        .allocator = allocator,
        .tape = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Interpreter) void {
    self.tape.deinit();
}

pub fn execute(
    self: *Interpreter,
    code: []const u8,
    comptime ReaderType: type,
    reader: ReaderType,
    comptime WriterType: type,
    writer: WriterType,
) !void {
    if (code.len == 0) return error.EmptyCode;

    var lexer = Lexer.init(self.allocator);
    defer lexer.deinit();

    try lexer.tokenize(code);

    try self.tape.append(0);

    const tokens = lexer.getTokens();
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        switch (token) {
            .inc_ptr => {
                const count = lexer.getConsecutiveTokens(i);
                try self.incPtr(count);
                i += count - 1;
            },
            .dec_ptr => {
                const count = lexer.getConsecutiveTokens(i);
                try self.decPtr(count);
                i += count - 1;
            },
            .inc_val => {
                const count = lexer.getConsecutiveTokens(i);
                self.valOp(count, .pos);
                i += count - 1;
            },
            .dec_val => {
                const count = lexer.getConsecutiveTokens(i);
                self.valOp(count, .neg);
                i += count - 1;
            },
            .loop_start => {
                if (self.tape.items[self.dptr] == 0) i = lexer.loopEndFromLoopStart(i);
            },
            .loop_end => {
                if (self.tape.items[self.dptr] != 0) i = lexer.loopStartFromLoopEnd(i);
            },
            .input => {
                const byte = reader.readByte() catch |err| {
                    if (err == error.EndOfStream) {
                        self.tape.items[self.dptr] = 0;
                        continue;
                    } else {
                        return error.Input;
                    }
                };
                self.tape.items[self.dptr] = byte;
            },
            .output => {
                const byte = self.tape.items[self.dptr];
                writer.writeByte(byte) catch return error.Output;
            },
        }
    }
}

const tape_growth_factor = 2;

fn incPtr(self: *Interpreter, count: usize) !void {
    if (self.dptr + count >= self.tape.items.len) {
        const old_size = self.tape.items.len;
        const new_size = @max(
            self.dptr + count + 1,
            self.tape.items.len * tape_growth_factor,
        );
        try self.tape.resize(new_size);
        for (self.tape.items[old_size..]) |*cell| {
            cell.* = 0;
        }
    }

    self.dptr += count;
}

fn decPtr(self: *Interpreter, count: usize) !void {
    const dptr_i64: i64 = @intCast(self.dptr);
    const count_i64: i64 = @intCast(count);
    if (dptr_i64 - count_i64 < 0) return error.NegativePointer;

    self.dptr -= count;
}

fn valOp(self: *Interpreter, count: usize, sign: enum { pos, neg }) void {
    const max = math.maxInt(u8);
    var remaining = count;
    while (remaining > @as(usize, max)) {
        remaining -= @as(usize, max);
        switch (sign) {
            .pos => self.tape.items[self.dptr] +%= @as(u8, max),
            .neg => self.tape.items[self.dptr] -%= @as(u8, max),
        }
    }
    switch (sign) {
        .pos => self.tape.items[self.dptr] +%= @as(u8, @intCast(remaining)),
        .neg => self.tape.items[self.dptr] -%= @as(u8, @intCast(remaining)),
    }
}

/// Return value (program output) must be freed by caller
fn runTest(
    self: *Interpreter,
    allocator: mem.Allocator,
    code: []const u8,
    input: []const u8,
) ![]const u8 {
    const Reader = std.io.FixedBufferStream([]const u8).Reader;
    var input_buf = std.io.fixedBufferStream(input);
    const reader = input_buf.reader();

    const Writer = std.ArrayList(u8).Writer;
    var output_buf = std.ArrayList(u8).init(allocator);
    errdefer output_buf.deinit();
    const writer = output_buf.writer();

    try self.execute(code, Reader, reader, Writer, writer);
    return output_buf.toOwnedSlice();
}

const testing = std.testing;

test "pointer movement" {
    const code = ">><.";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 1);
    try testing.expectEqual(output[0], 0);
}

test "value operations" {
    const code = "+++.>+++--.";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 2);
    try testing.expectEqual(output[0], 3);
    try testing.expectEqual(output[1], 1);
}

test "value wrapping" {
    const code = "--.";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 1);
    try testing.expectEqual(output[0], 254);
}

test "basic loop" {
    const code = "+++++[.-]";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 5);
    try testing.expectEqual(output[0], 5);
    try testing.expectEqual(output[1], 4);
    try testing.expectEqual(output[2], 3);
    try testing.expectEqual(output[3], 2);
    try testing.expectEqual(output[4], 1);
}

test "nested loops" {
    const code = "++[.->++[.-]<]";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 6);
    try testing.expectEqual(output[0], 2);
    try testing.expectEqual(output[1], 2);
    try testing.expectEqual(output[2], 1);
    try testing.expectEqual(output[3], 1);
    try testing.expectEqual(output[4], 2);
    try testing.expectEqual(output[5], 1);
}

test "input handling" {
    const code = ",.,.";
    const input = "AB";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 2);
    try testing.expectEqual(output[0], 'A');
    try testing.expectEqual(output[1], 'B');
}

test "input EOF handling" {
    const code = ",.,.,.";
    const input = "A";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 3);
    try testing.expectEqual(output[0], 'A');
    try testing.expectEqual(output[1], 0);
    try testing.expectEqual(output[2], 0);
}

test "tape growth" {
    const code = ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>.";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    const output = try inter.runTest(testing.allocator, code, input);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 1);
    try testing.expectEqual(output[0], 0);
}

test "empty code error" {
    const code = "";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    try testing.expectError(
        error.EmptyCode,
        inter.runTest(testing.allocator, code, input),
    );
}

test "no valid tokens error" {
    const code = "no valid tokens";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    try testing.expectError(
        error.NoValidTokens,
        inter.runTest(testing.allocator, code, input),
    );
}

test "negative pointer error" {
    const code = "<";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    try testing.expectError(
        error.NegativePointer,
        inter.runTest(testing.allocator, code, input),
    );
}

test "unmatched loop start error" {
    const code = "[";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    try testing.expectError(
        error.UnmatchedLoopStart,
        inter.runTest(testing.allocator, code, input),
    );
}

test "unmatched loop end error" {
    const code = "]";
    const input = "";

    var inter = Interpreter.init(testing.allocator);
    defer inter.deinit();

    try testing.expectError(
        error.UnmatchedLoopEnd,
        inter.runTest(testing.allocator, code, input),
    );
}
