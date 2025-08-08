var exports = {};
exports.start = start;
import * as wasm from "./wasm.js";

const O_flags = {
	CREAT: 0b01,
	EXCL: 0b10,
};

export function start() {
	var cwd_fd = wasm.open("/home/natural/", O_flags.CREAT);
	var cwd_string = normalizePath(wasm.getcwd(cwd_fd));
	var prompt = "N@castle:" + cwd_string + "$ ";
	var restricted_text = prompt;
	const commands = new Map([
		["echo", echo],
		["printf", printf],
		["pwd", pwd],
		["clear", clear],
		[ "cd", cd ],
		// [ "exit", exit ],
	]);

	$("textarea").on("input", function () {
		let val = String($(this).val());
		if (val.indexOf(restricted_text) == -1) {
			$(this).val(restricted_text);
		}
		// If the user has pressed enter
		if (val.charCodeAt(val.length - 1) == 10) {
			let args = parse_cmdline(
				val.slice(val.lastIndexOf(prompt) + prompt.length).trimEnd(),
			);
			if (args[0] == pwd) args[1] = cwd_fd; // special case for pwd

			try {
                // special case for cwd as it needs to update variables
				if (args[0] == "cd") {
                    return_args = cd(args, cwd_fd, cwd_string);
                    cwd_fd = return_args[0];
                    cwd_string = return_args[1];
                    prompt = "N@castle:" + cwd_string + "$ ";
				} else {
                    // call function with name args[0] and arguments args
                    commands.get(args[0])(args);
                }
			} catch (e) {
				if (e) {
					println(e);
                    throw e;
				} else {
					println(args[0] + ": command not found");
				}
			}

			// print prompt (special case for "clear")
			if (args[0] == "clear") {
				print(prompt);
			} else {
				print("\n" + prompt);
			}

			restricted_text = $(this).val();
		}
	});
}

// API INFO (i = in progress, x = done)
// [ ] readLine (see: bash/readline)
// [ ] history (see: bash/history)
// [ ] cd (see: bash/shell builtin commands/cd)
// [i] echo (see: bash/shell builtin commands/echo)
// [ ] exit (see: bash/shell builtin commands/exit)
// [i] printf (see: bash/shell builtin commands/printf)
// [x] pwd (see: bash/shell builtin commands/pwd)
// [ ] read (see: bash/shell builtin commands/read)
// [ ] test (see: bash/shell builtin commands/test)

function clear() {
	$("textarea").val("");
}

function echo(args) {
	if (args[1] == "-n") {
		print(args.slice(2).join(" "));
		return;
	}
	print(args.slice(1).join(" ") + "\n");
}

// as of yet this works only for %s and %d
function printf(args) {
	let format = args[0];
	args = args.slice(1);
	let regex =
		/%(\$[0-9]+)?([#0\- +'])?([0-9]+)?(\.[0-9]+)?(hh|h|ll|l|L)?([sdiouxf%])/g;
	let specifiers = regex.exec(format);
	if (specifiers == null) return format;

	// for every arg, check if specifier is valid and replace it
	for (var i = 0; i < args.length; i++) {
		switch (typeof args[i]) {
			case "string":
				if (specifiers[i].at(-1) != "s") return "Err: Invalid specifier";
				break;
			case "number":
				if (specifiers[i].at(-1) != "d") return "Err: Invalid specifier";
				break;
			case "boolean":
				break;
		}
		format = format.replace(specifiers[i], args[i]);
	}
	$("textarea").val($("textarea").val() + format + "\n");
}

function cd(args, original_fd, cwd_string) {
    let new_fd = original_fd;
	// if there is 1 arg
	if (args[1] && !args[2]) {
		// if command is "cd .."
		if (args[1] == "..") {
            new_fd = wasm.open(cwd_string.slice(0, cwd_string.lastIndexOf("/"), 0));
		} else {
            let files = wasm.read(original_fd).split("\n");
            // check if arg exists
            if (files.indexOf(args[1] + "/") == -1) {
                println('cd: The directory "' + args[1] + '" does not exist');
                return [original_fd, cwd_string];
            } else {
                // cwd += "/" + args[1];
            }
        }
	} else if (!args[1]) {
		// if "cd" is ran by itself
		cwd = "~";
	} else {
		// if there are too many commands
		println("Too many args for cd command");
        return [original_fd, cwd_string];
	}
    wasm.close(original_fd);
    return [new_fd, wasm.getcwd(new_fd)];
}

function pwd(args) {
	println(wasm.getcwd(args[1]));
}

function println(input = "") {
	print(input + "\n");
}

function print(input) {
	$("textarea").val($("textarea").val() + input);
}

function normalizePath(path) {
	return path.replace("/home/natural/", "~");
}

function parse_cmdline(cmdline) {
	var re_next_arg = /^\s*((?:(?:"(?:\\.|[^"])*")|(?:'[^']*')|\\.|\S)+)\s*(.*)$/;
	var next_arg = ["", "", cmdline];
	var args = [];
	while ((next_arg = re_next_arg.exec(next_arg[2]))) {
		var quoted_arg = next_arg[1];
		var unquoted_arg = "";
		while (quoted_arg.length > 0) {
			if (/^"/.test(quoted_arg)) {
				var quoted_part = /^"((?:\\.|[^"])*)"(.*)$/.exec(quoted_arg);
				unquoted_arg += quoted_part[1].replace(/\\(.)/g, "$1");
				quoted_arg = quoted_part[2];
			} else if (/^'/.test(quoted_arg)) {
				var quoted_part = /^'([^']*)'(.*)$/.exec(quoted_arg);
				unquoted_arg += quoted_part[1];
				quoted_arg = quoted_part[2];
			} else if (/^\\/.test(quoted_arg)) {
				unquoted_arg += quoted_arg[1];
				quoted_arg = quoted_arg.substring(2);
			} else {
				unquoted_arg += quoted_arg[0];
				quoted_arg = quoted_arg.substring(1);
			}
		}
		args[args.length] = unquoted_arg;
	}
	for (let i = 0; i < args.length; i++) {
		if (parseInt(args[i])) {
			args[i] = parseInt(args[i]);
		}
	}
	return args;
}

//
// function idk(args) {
// 	cli.print("test");
// }
//
// function println(input = "") {
// 	cli.println(input);
// }
//
// function print(input) {
// 	cli.print(input);
// }
//
// function clear() {
// 	cli.clear();
// }
//
//
// function ls(args) {
// 	let outputArr = [];
// 	getWDFiles().forEach((e) => {
// 		if (args.indexOf("-a") != -1) {
// 			// print all if the "-a" argument was added
// 			print(e + "  ");
// 		} else {
// 			// otherwise do not print hidden files or dirs
// 			if (e[0] != ".") {
// 				outputArr.push(e);
// 			}
// 		}
// 	});
// 	// only print anything if there is anything to print
// 	if (outputArr.length != 0) {
// 		println(outputArr.join("  "));
// 	}
// }
//
// function mkdir(args) {
// 	if (!args[1]) {
// 		println("mkdir: missing operand");
// 	} else {
// 		args.forEach((element) => {
// 			if (element == "mkdir" || element.includes("/")) {
// 				return;
// 			}
// 			fs.push(cwd + "/" + element + "/");
// 		});
// 	}
// }
//
// function rm(args) {
// 	if (args[1] == "-rf") {
// 		println("hahaha so funny");
// 		return;
// 	}
// }
//
// function getWDFiles() {
// 	let returnArr = [];
// 	fs.forEach((element) => {
// 		if (element.indexOf(cwd) != -1) {
// 			element = element.slice(element.indexOf(cwd) + cwd.length + 1);
// 			if (element.length == 0) {
// 				return;
// 			}
// 		} else {
// 			return;
// 		}
// 		if (
// 			element.indexOf("/") == -1 ||
// 			element.indexOf("/") == element.length - 1
// 		) {
// 			returnArr.push(element);
// 		}
// 	});
// 	return returnArr;
// }
