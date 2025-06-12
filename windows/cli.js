function println(input = "") {
	$("textarea").val($("textarea").val() + input + "\n");
}

function print(input) {
	$("textarea").val($("textarea").val() + input);
}

function clear() {
	$("textarea").val("");
}

module.exports = {
	println,
	print,
	clear,
};
