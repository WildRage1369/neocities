import { createWindow, insert, insertFile } from "./js/window_manager.js";
import { ProcessTree } from "./js/process_tree.js";
var exports = {};
exports.kernel = kernel;
exports.programs = programs;
exports.processTree = processTree;

var wasm_instance; // inited in runWasm
var freeString;
export var kernel = {};
export var programs = {};
export var processTree;

function stringToPointer(str) {
	const buffer = new TextEncoder().encode(str);
	const pointer = _allocString(buffer.length); // ask Zig to allocate memory
	const slice = new Uint8Array(
		wasm_instance.instance.exports.memory.buffer, // memory exported from Zig
		pointer,
		buffer.length + 1,
	);
	slice.set(buffer);
	slice[buffer.length] = 0; // null byte to null-terminate the string
	return pointer;
}

export function pointerToString(ptr) {
	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(wasm_instance.instance.exports.memory.buffer);
	// get len of string
	let ptr_cpy = ptr;
	let len = 0;
	while (view[ptr_cpy] != 0 && len < 99999) {
		len++;
		ptr_cpy++;
	}
    if (len == 99999) { return "ERROR: string too long"; }
	let str = utf8Decoder.decode(view.slice(ptr, ptr + len));
	return str;
}

export function procPointerToString(pid, ptr) {
	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(processTree.get(pid).memory.buffer);
	// get len of string
	let ptr_cpy = ptr;
	let len = 0;
	while (view[ptr_cpy] != 0 && len < 99999) {
		len++;
		ptr_cpy++;
	}
    if (len == 99999) { return "ERROR: string tooo long"; }
	let str = utf8Decoder.decode(view.slice(ptr, ptr + len));
	return str;
}

function pointerToStringDealloc(ptr) {
	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(wasm_instance.instance.exports.memory.buffer);
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

const importFunctions = {
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
		createWindow,
		insert,
		insertFile,
		loadProgram(name_ptr) {
			let program_name = pointerToString(name_ptr);

			WebAssembly.instantiateStreaming(
				fetch("/programs/" + program_name + ".zig.wasm"),
				importFunctions,
			).then((wasm) => {
                let pid = processTree.addProcess(program_name, 1, 1, wasm.instance.exports.memory);
				programs[program_name] = wasm.instance.exports["main"];
				console.log("program loaded: " + program_name + " " + pid);
				programs[program_name](pid);
			});
		},
	},
};

WebAssembly.instantiateStreaming(fetch("/kernel.wasm"), importFunctions).then(
	(wasm) => {
		for (const elem in wasm.instance.exports) {
			kernel[elem] = wasm.instance.exports[elem];
		}
		wasm_instance = wasm;

        processTree = new ProcessTree(wasm.instance.exports.memory);
		kernel.start();
	},
);
