const std = @import("std");
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const process = std.process;
const log = std.log;

const Interpreter = @import("Interpreter.zig");

const success = 0;
const arg_error = 1;
const syntax_error = 2;
const input_error = 3;
const output_error = 4;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args_iter = try process.ArgIterator.initWithAllocator(allocator);
    defer args_iter.deinit();
    if (!args_iter.skip()) unreachable;

    var code: []const u8 = undefined;
    if (args_iter.next()) |arg| {
        code = arg;
    } else {
        log.err("Expected code as argument", .{});
        return arg_error;
    }

    if (args_iter.next()) |_| {
        log.err("Too many arguments (expected 1)", .{});
        return arg_error;
    }

    const Reader = fs.File.Reader;
    const stdin = io.getStdIn();
    const Writer = fs.File.Writer;
    const stdout = io.getStdOut();

    var inter = Interpreter.init(allocator);
    defer inter.deinit();

    inter.execute(code, Reader, stdin.reader(), Writer, stdout.writer()) catch |err| switch (err) {
        error.UnmatchedLoopStart => {
            log.err("Unmatched loop start", .{});
            return syntax_error;
        },
        error.UnmatchedLoopEnd => {
            log.err("Unmatched loop end", .{});
            return syntax_error;
        },
        error.EmptyCode => {
            log.err("No valid operations in input stream", .{});
            return syntax_error;
        },
        error.NegativePointer => {
            log.err("Data pointer negative", .{});
            return syntax_error;
        },
        error.Input => {
            log.err("Cannot read from input stream", .{});
            return input_error;
        },
        error.Output => {
            log.err("Cannot write to output stream", .{});
            return output_error;
        },
        else => return err,
    };

    return success;
}
