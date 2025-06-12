// FileSystemTree is a tree of INodes,
// INodes are files and directories
class FileSystemTree {
	#root;
	#file_data_map;
	#serial_number_counter = 1;

	constructor() {
		// create root node with rwxr-xr-x perms
		root = new INode(
			"/",
			this.getSerialNum(),
			0,
			Timestamp.currentTime(),
			0o755,
		);

		// create base directories
		let root_children = [
			new INode("tmp", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755),
			new INode("home", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755),
			new INode("bin", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755),
			new INode("dev", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755),
		];
		root.addChildList(root_children);
	}

	// @returns serial number pre-incremented
	getSerialNum() {
		return this.#serial_number_counter++;
	}

	// @param file_path: string full path to file
	// @param flags: int W_Flags
	// @param data: string data to write
	// @returns number of bytes written
	// @returns -1 if file already exists and W_Flags.EXCL is set
	// @returns -2 if file_path is not found
	write(file_path, flags, data) {
		//check if file exists
		let file = this.#getFile(file_path);

		// if file already exists and W_Flags.EXCL, error out
		if (flags & W_Flags.EXCL && file != undefined) {
			return -1;
		}

		// create file if it doesn't exist and W_Flags.CREAT is set
		if (flags & W_Flags.CREAT && file == undefined) {
			let dir = this.#getFile(file_path.slice(0, file_path.lastIndexOf("/")));
			if (dir == undefined) {
				return -2;
			}

			// create file
			dir.addChildINode(
				new INode(
					file_path.slice(file_path.lastIndexOf("/") + 1),
					this.getSerialNum(),
					data.length,
					Timestamp.currentTime(),
					0o755,
				),
			);
		}

		if (file == undefined) {
			return -2;
		}

		// write data to file
		if (flags & W_Flags.APPEND) {
			this.#file_data_map[file.serial_number] += data;
		} else if (flags & W_Flags.TRUNC) {
			this.#file_data_map[file.serial_number] = data;
		}

		return data.length;
	}

	// @param file_path: string full path to file
	// @returns string data read from file
	read(file_path) {
		let file = this.#getFile(file_path);
		if (file == undefined) {
			return -2;
		}
		return this.#file_data_map[file.serial_number];
	}

	// returns the INode of the file located at file_path
	// @param file_path: string
	#getFile(file_path) {
		let path_list = file_path.split("/");
		let current = this.#root;
		// iterate through dirs
		for (let node of path_list) {
			// search for subdirectory/file
			current = current.children.find((e) => e.name == node);

			if (current == undefined) {
				return undefined;
			}
		}
		return current;
	}
}

const W_Flags = {
	APPEND: 1,
	CREAT: 2,
	EXCL: 3,
	TRUNC: 4,
};

class INode {
	serial_number;
	name;
	file_mode; // file permissions
	owner; // user id
	timestamp; // Timestamp object with ctime, mtime, atime
	size;
	children; // list of INodes

	constructor(
		name,
		serial_number,
		owner,
		timestamp,
		file_mode,
		size = 0,
		children = [],
	) {
		this.name = name;
		this.serial_number = serial_number;
		this.file_mode = file_mode;
		this.owner = owner;
		this.timestamp = timestamp;
		this.size = size;
		this.children = children;
	}

	// add a child INode to this INode
	addChildINode(child) {
		children.push(child);
	}

	// add a list of children INodes to this INode
	addChildList(new_children) {
		children.concat(new_children);
	}

	isDirectory() {
		return this.children.length > 0;
	}
}

class Timestamp {
	ctime = 0;
	mtime = 0;
	atime = 0;

	static currentTime() {
		return new Timestamp(
			new Date().getTime(),
			new Date().getTime(),
			new Date().getTime(),
		);
	}
}
