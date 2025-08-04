let request = new XMLHttpRequest();
// import * as cli from "./terminal.js";
request.open("GET", "/lib/wasm_runner.wasm");
request.responseType = "arraybuffer";
request.send();

var wasm; // inited in runWasm
var init, _allocString, _open, _write, _read, _getcwd, freeString;

function runWasm(result) {
	wasm = result;
	init = result.instance.exports.init;
    freeString = result.instance.exports.freeString;
	_open = result.instance.exports.open;
	_write = result.instance.exports.write;
	_read = result.instance.exports.read;
	_allocString = result.instance.exports.allocString;
    _getcwd = result.instance.exports.getcwd;

	init();

    start();
}

export function open(path, flags) {
    return _open(stringToPointer(path), flags);
}

export function write(fd, data) {
    return _write(fd, stringToPointer(data));
}

export function read(fd) {
    return pointerToString(_read(fd));
}

export function getcwd(fd) {
    return pointerToString(_getcwd(fd));
}

function stringToPointer(str) {
	const buffer = new TextEncoder().encode(str);
	const pointer = _allocString(buffer.length); // ask Zig to allocate memory
	const slice = new Uint8Array(
		wasm.instance.exports.memory.buffer, // memory exported from Zig
		pointer,
		buffer.length + 1,
	);
	slice.set(buffer);
	slice[buffer.length] = 0; // null byte to null-terminate the string
	return pointer;
}
function pointerToString(ptr) {
	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(wasm.instance.exports.memory.buffer);
    // get len of string
	let ptr_cpy = ptr;
	let len = 0;
	while (view[ptr_cpy] != 0) {
		len++;
		ptr_cpy++;
	}
    let str = utf8Decoder.decode(view.slice(ptr, ptr + len));
	return str
}

function pointerToStringDealloc(ptr) {
	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(wasm.instance.exports.memory.buffer);
    // get len of string
	let ptr_cpy = ptr;
	let len = 0;
	while (view[ptr_cpy] != 0) {
		len++;
		ptr_cpy++;
	}
    let str = utf8Decoder.decode(view.slice(ptr, ptr + len));
    freeString(ptr, len);
	return str
}

request.onload = function () {
	var bytes = request.response;
	WebAssembly.instantiate(bytes, {
		env: {
			logNum(data) {
				console.log(data);
			},
			logStr(ptr) {
				console.log(pointerToString(ptr));
			},
			logErr(ptr) {
				console.error("Panic: " + pointerToString(ptr));
			},
		},
	}).then(runWasm);
};

const O_flags = {
    CREAT: 0b01,
    EXCL: 0b10,
}

function start() {
	var cwd = open("/home/natural/", O_flags.CREAT);
    var pwd = getcwd(cwd);
	var prompt = "N@castle:" + pwd + "$ ";
	var restricted_text = prompt;
	var fs = [
		"~/.bashrc",
		"~/Desktop/",
		"~/Idk/",
		"~/Idk/wow.bat",
		"~/Idk/fol/",
		"~/Idk/fol/test.txt",
	];

	$("textarea").on("input", function () {
		let val = String($(this).val());
		if (val.indexOf(restricted_text) == -1) {
			$(this).val(restricted_text);
		}
		// If the user has pressed enter
		if (val.charCodeAt(val.length - 1) == 10) {
			let args = val
				.slice(val.lastIndexOf(prompt) + prompt.length)
				.trimEnd()
				.split(" ");
			try {
				// call function with name args[0] and arguments args
				window[args[0]](args);
			} catch {
				println(args[0] + ": command not found");
			}
			if (window[args[0]] == "clear") {
				$(this).val($(this).val() + "\n" + prompt);
			}
			restricted_text = $(this).val();
		}
	});
}

function pwd(args) {
    println(getcwd(args[0]));
}

function println(input = "") {
	$("textarea").val($("textarea").val() + input + "\n");
}

function print(input) {
	$("textarea").val($("textarea").val() + input);
}

function clear() {
	$("textarea").val("");
}
