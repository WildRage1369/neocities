
// name: []const u8,
// state: enum { running, waiting, stopped, zombie },
// pid: u32,
// ppid: u32,
// uid: u32,
// cwd: usize, // inode
// memory: ?

export class Process {
    name;
    state;
    pid;
    ppid;
    uid;
    memory;

    constructor(name, state, pid, ppid, uid, memory) {
        this.name = name;
        this.state = state;
        this.pid = pid;
        this.ppid = ppid;
        this.uid = uid;
        this.memory = memory;
    }
}

export class ProcessTree {
    processes;
    root = 1;
    max_pid = 1;

    constructor(memory) {
        this.processes = [];
        this.processes.push(new Process("kernel", "running", 1, 1, 1, memory))
        this.root = 1;
    }

    addProcess(name, ppid, uid, memory) {
        console.log("addProcess running with name: " + name + " and ppid: " + ppid + " and uid: " + uid + " and memory: " + memory);
        this.max_pid++;
        this.processes.push(new Process(name, "running", this.max_pid, ppid, uid, memory));
        return this.max_pid;
    }

    get(pid) {
        // return pid
        return this.processes.find((process) => process.pid === pid);
    }

    getParent(pid) {
        return this.getProcess(pid).ppid;
    }

    getChildren(pid) {
        return this.processes.filter((process) => process.ppid === pid);
    }

    getSiblings(pid) {
        return this.processes.filter((process) => process.ppid === this.getParent(pid));
    }

    getChildrenOf(pid) {
        return this.getChildren(this.getParent(pid));
    }

    getSiblingsOf(pid) {
        return this.getSiblings(this.getParent(pid));
    }
}
