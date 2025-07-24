let request = new XMLHttpRequest();
request.open("GET", "/lib/wasm_runner.wasm");
request.responseType = "arraybuffer";
request.send();

var wasm; // inited in runWasm
var init, _allocString, _open, _write, _read;

function runWasm(result) {
	wasm = result;
	init = result.instance.exports.init;
	_open = result.instance.exports.open;
	_write = result.instance.exports.write;
	_read = result.instance.exports.read;
	_allocString = result.instance.exports.allocString;

	init();

	// basic file ops as of 2025-07-24
	let fd = open("/tmp/test.txt");

	let bytes_written = write(fd, "test");

	let bytes_read = read(fd);
}

function open(path) {
    return _open(stringToPointer(path));
}

function write(fd, data) {
    return _write(fd, stringToPointer(data));
}

function read(fd) {
    return pointerToString(_read(fd));
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
	let ptr_cpy = ptr;
	let len = 0;
	while (view[ptr_cpy] != 0) {
		len++;
		ptr_cpy++;
	}
	return utf8Decoder.decode(view.slice(ptr, ptr + len));
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
