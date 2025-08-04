
function idk(args) {
	cli.print("test");
}

function println(input = "") {
	cli.println(input);
}

function print(input) {
	cli.print(input);
}

function clear() {
	cli.clear();
}

function cd(args) {
	// if there is 1 arg
	if (args[1] && !args[2]) {
		// if command is "cd .."
		if (args[1] == "..") {
			//go up a directory
			cwd = cwd.slice(0, cwd.lastIndexOf("/"));
			prompt = "N@castle:" + cwd + "$ ";
			return;
		}
		//get all files in dir
		let files = getWDFiles();
		// check if arg exists
		if (files.indexOf(args[1] + "/") == -1) {
			println('cd: The directory "' + args[1] + '" does not exist');
		} else {
			cwd += "/" + args[1];
		}
	} else if (!args[1]) {
		// if "cd" is ran by itself
		cwd = "~";
	} else {
		// if there are too many commands
		println("Too many args for cd command");
	}
	prompt = "N@castle:" + cwd + "$ ";
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
			fs.push(cwd + "/" + element + "/");
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
		if (element.indexOf(cwd) != -1) {
			element = element.slice(element.indexOf(cwd) + cwd.length + 1);
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
