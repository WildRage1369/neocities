var shellLocation = "~";
var shellPrompt = "N@castle:" + shellLocation + "$ ";
var requiredText = shellPrompt;
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
	if (val.indexOf(requiredText) == -1) {
		$(this).val(requiredText);
	}

	// If the user has pressed enter
	if (val.charCodeAt(val.length - 1) == 10) {
		let args = val
			.slice(val.lastIndexOf(shellPrompt) + shellPrompt.length)
			.trimEnd()
			.split(" ");
		try {
			// call function with name args[0] and arguments args
			window[args[0]](args);
		} catch {
			println(args[0] + ": command not found");
		}
		$(this).val($(this).val() + "\n" + shellPrompt);
		requiredText = $(this).val();
	}
});

function println(input = "") {
	$("textarea").val($("textarea").val() + input + "\n");
}

function print(input) {
	$("textarea").val($("textarea").val() + input);
}

function clear() {
	$("textarea").val("");
}

function cd(args) {
	// if there is 1 arg
	if (args[1] && !args[2]) {
		// if command is "cd .."
		if (args[1] == "..") {
			//go up a directory
			shellLocation = shellLocation.slice(0, shellLocation.lastIndexOf("/"));
			shellPrompt = "N@castle:" + shellLocation + "$ ";
			return;
		}
		//get all files in dir
		let files = getWDFiles();
		// check if arg exists
		if (files.indexOf(args[1] + "/") == -1) {
			println('cd: The directory "' + args[1] + '" does not exist');
		} else {
			shellLocation += "/" + args[1];
		}
	} else if (!args[1]) {
		// if "cd" is ran by itself
		shellLocation = "~";
	} else {
		// if there are too many commands
		println("Too many args for cd command");
	}
	shellPrompt = "N@castle:" + shellLocation + "$ ";
}

function ls(args) {
	let outputArr = [];
	getWDFiles().forEach((e) => {
		if (args.indexOf("-a") != -1) {
			// print all if the "-a" argument was added
			print(e + "  ");
		} else {
			// otherwise do not print hidden files or dirs
			if (e[0] != ".") {
				outputArr.push(e);
			}
		}
	});
	// only print anything if there is anything to print
	if (outputArr.length != 0) {
		println(outputArr.join("  "));
	}
}

function mkdir(args) {
	if (!args[1]) {
		println("mkdir: missing operand");
	} else {
		args.forEach((element) => {
			if (element == "mkdir" || element.includes("/")) {
				return;
			}
			fs.push(shellLocation + "/" + element + "/");
		});
	}
}

function rm(args) {
	if (args[1] == "-rf") {
		println("hahaha so funny");
		return;
	}
}

function getWDFiles() {
	let returnArr = [];
	fs.forEach((element) => {
		if (element.indexOf(shellLocation) != -1) {
			element = element.slice(
				element.indexOf(shellLocation) + shellLocation.length + 1,
			);
			if (element.length == 0) {
				return;
			}
		} else {
			return;
		}
		if (
			element.indexOf("/") == -1 ||
			element.indexOf("/") == element.length - 1
		) {
			returnArr.push(element);
		}
	});
	return returnArr;
}
