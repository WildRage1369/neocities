import { start } from "./terminal.js";
var exports = {};
exports.open = open;
exports.write = write;
exports.read = read;
exports.getcwd = getcwd;

let request = new XMLHttpRequest();
request.open("GET", "/lib/wasm_runner.wasm");
request.responseType = "arraybuffer";
request.send();

var wasm; // inited in runWasm
var init, _allocString, _open, _close, _write, _read, _getcwd, freeString;


function runWasm(result) {
	wasm = result;
	init = result.instance.exports.init;
	freeString = result.instance.exports.freeString;
	_open = result.instance.exports.open;
    _close = result.instance.exports.close;
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

export function close(fd) {
    return _close(fd);

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
	return str;
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
	return str;
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
