let request = new XMLHttpRequest();
request.open("GET", "/lib/wasm_runner.wasm");
request.responseType = "arraybuffer";
request.send();

var wasm; // inited in runWasm
var init, allocString, open, write, read;

function runWasm(result) {
	wasm = result;
	init = result.instance.exports.init;
	open = result.instance.exports.open;
	write = result.instance.exports.write;
	read = result.instance.exports.read;
	allocString = result.instance.exports.allocString;

	init();

	// basic file ops as of 2025-07-24
		console.log("Opening file...");
		let serialNum = open(stringToPointer("/tmp/test.txt"));
		console.log("Serial number: " + serialNum);

		console.log("Writing to file...");
		let bytes_written = write(serialNum, stringToPointer("test"));
		console.log("Bytes written: " + bytes_written);

		console.log("Reading from file...");
		let bytes_read = pointerToString(read(serialNum));
		console.log("Bytes read: " + bytes_read);
}

function stringToPointer(str) {
	const buffer = new TextEncoder().encode(str);
	const pointer = allocString(buffer.length); // ask Zig to allocate memory
	const slice = new Uint8Array(
		wasm.instance.exports.memory.buffer, // memory exported from Zig
		pointer,
		buffer.length + 1,
	);
	slice.set(buffer);
	slice[buffer.length] = 0; // null byte to null-terminate the string
	return pointer;

	// let utf8Encoder = new TextEncoder();
	// let view = new Uint8Array(wasm.instance.exports.memory.buffer);
	// let len = utf8Encoder.encode(str).length;
	//
	// let ptr = allocString(len);
	//    view[ptr] = utf8Encoder.encode(str);
	// // view[ptr + len] = 0;
	//    console.log(ptr);
	// return ptr;
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
