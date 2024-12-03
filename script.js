var runningWindows = {};
var next_wid = 1;
var wid = 0;
var mouseUp = true;
var mousePosition;
var titles = [
	["abtme", "About Me :3"],
	["abtsite", "About My Site!"],
	["links", "My Links!"],
	["pronouns", "My Pronoun Prefrence!"],
	["pictures", "N <3 <3"],
	["jukebox", "Jukebox"],
	["terminal", "Terminal"],
	["blogs", "My Blog Posts"],
	["clock", "Clock"],
	["why-n", "Why N?"],
	["buttons", "Buttons!"],
];

$(document).on("mousedown", () => {
	mouseUp = false;
});
$(document).on("mouseup", () => {
	mouseUp = true;
});

function insertWindow(dirname) {
	let dim = [$(document).width(), $(document).height()];
	// set the cursor to wait to let the user know that their input was registered
	// parent.document.body.style.cursor = "wait";
	// document.body.style.cursor = "wait";
	let title = "";
	let basename = "";
	titles.forEach((cur_title) => {
		if (dirname.includes(cur_title[0])) {
			basename = cur_title[0];
			title = cur_title[1];
		}
	});

	wid = next_wid++; // get the window ID for the new window

	let window_html = `
        <div class="window ${dirname}-win" id="win-${wid}">
        <div class="title-bar">
        <div class="title-bar-text unselectable">${title}</div>
        <div class="title-bar-controls">
        <button id="min-${wid}" aria-label="Minimize"></button>
        <button id="cls-${wid}" aria-label="Close"></button>
        </div>
        </div>
        <iframe src="windows/${dirname}.html" id=${basename} class=frame style=""></iframe>
        </div>`;
	// <button id=taskbar-${dirname} type="button" class="window-button">
	let taskbar_html = `
        <button id="bar-${wid}" type="button" class="window-button taskbar-button">
        <p id="par-${wid}" class="button-text">${title}</p>
        </button>`;

	runningWindows[wid] = {
		wid: wid,
		basename: basename,
		visible: true,
		down: false,
		offset: [0, 0],
		z_index: 1,
		jqWin: $(window_html).appendTo($(".container"))[0],
		jqBarButton: $(taskbar_html).appendTo($("#taskbar-left"))[0],
	};
	let win = runningWindows[wid];

	// increment the z-indeces of all windows and redistribute
	Object.keys(runningWindows).forEach((key) => {
		if (key != wid) {
			runningWindows[key].z_index++;
		}
	});
	redistribute();

	// taskbar button
	$(":button[id='bar-" + wid + "']").on("click", () => {
		if (win.z_index == 1) {
			// if win is selected (requires window to be visible)
			win.visible = false;
			$(win.jqWin).toggle();
			toBack(win.wid);
		} else if (win.visible) {
			// if win is visble but not selected
			toFront(win.wid);
		} else {
			// if win is hidden
			win.visible = true;
			$(win.jqWin).toggle();
			toFront(win.wid);
		}
	});

	// minimize button (window)
	$(":button[id='min-" + wid + "']").on("click", () => {
		// hide the window and set it's 'visible' property to false
		win.visible = false;
		$(win.jqWin).toggle();
		// send to back of the window stack
		toBack(win.wid);
	});

	// close button (window)
	$(":button[id='cls-" + wid + "']").on("click", () => {
		// remove the window and button and remove the internal object
		$(win.jqWin).remove();
		$(win.jqBarButton).remove();
		delete runningWindows[win.wid];
	});

	// on mousedown event
	$(win.jqWin)
		.contents()
		.on("mousedown", (event) => {
			win.down = true;
			win.offset = [
				(win.offset.x = event.clientX - parseInt($(win.jqWin).css("left"))),
				(win.offset.y = event.clientY - parseInt($(win.jqWin).css("top"))),
			];
			toFront(win.wid);
		});
	// on mousemove event
	$(win.jqWin)
		.contents()
		.on("mousemove", (event) => {
			if (win.down) {
				$(win.jqWin).css("left", event.pageX - win.offset[0]);
				$(win.jqWin).css("top", event.pageY - win.offset[1]);
			}
		});
	// on mouseup event
	$(win.jqWin)
		.contents()
		.on("mouseup", () => {
			win.down = "";
		});

	// resize the iframe and set the position to the middle of the screen
	$(win.jqWin)
		.children("iframe")
		.on("load", (event) => {
			resizeIframe(win.jqWin);
			$(event.target)
				.parent(".window")
				.each((i, e) => {
					i++; // supresses warning
					if ($(e).css("left") == "9999px") {
						$(e).css("left", dim[0] / 2 - parseInt($(e).css("width")) / 2);
						$(e).css("top", dim[1] / 2 - parseInt($(e).css("height")) / 2);
					}
				});
			// move window to front when clicked even in iframe
			$(win.jqWin)
				.children("iframe")
				.contents()
				.eq(0)
				.on("mousedown", () => {
					toFront(win.wid);
				});

			// resize iframe and move to front when window is resized
			var timer_id;
			let counter = 0;
			$(win.jqWin).on("mousemove", () => {
				if (!mouseUp) {
					if (counter == 0) {
						timer_id = setTimeout(() => {
							toFront(win.wid);
							resizeIframeForResize(win.jqWin);
							counter = 0;
						}, 20);
						counter++;
					}
				}
			});
		});

	// return the cursor to normal
	parent.document.body.style.cursor = "auto";
	$(win.jqWin).contents().find("body").css("cursor", "auto");
}

// sends window with wid to back
function toBack(wid) {
	let old_z = runningWindows[wid].z_index;
	Object.keys(runningWindows).forEach((key) => {
		if (runningWindows[key].z_index > old_z) {
			runningWindows[key].z_index--;
		}
	});
	runningWindows[wid].z_index = Object.keys(runningWindows).length;
	redistribute();
}

// sends window with wid to front
function toFront(wid) {
	let old_z = runningWindows[wid].z_index;
	Object.keys(runningWindows).forEach((key) => {
		if (runningWindows[key].z_index < old_z) {
			runningWindows[key].z_index++;
		}
	});
	runningWindows[wid].z_index = 1;
	redistribute();
}

// redistributes window z-indeces acording to position in stack
function redistribute() {
	Object.keys(runningWindows).forEach((key) => {
		$(runningWindows[key].jqWin).css(
			"z-index",
			Object.keys(runningWindows).length - (runningWindows[key].z_index - 1),
		);
		if (runningWindows[key].z_index == 1) {
			$(runningWindows[key].jqWin)
				.children(".title-bar")
				.removeClass("inactive");
		} else {
			$(runningWindows[key].jqWin).children(".title-bar").addClass("inactive");
		}
	});
}

function resizeIframe(obj) {
	$(obj)
		.children("iframe")
		.css(
			"height",
			$(obj).children("iframe").contents().find("body").css("height"),
		);
	$(obj)
		.children("iframe")
		.css(
			"width",
			$(obj).children("iframe").contents().find("body").css("width"),
		);
}

function resizeIframeForResize(obj) {
	$(obj).children("iframe").css("width", $(obj).css("width"));
	let calc_height = Number($(obj).css("height").slice(0, -2)) - 25 + "px";
	$(obj).children("iframe").css("height", calc_height);
}

function resizeIframeDefault() {
	let obj = window.parent.$("#pictures")[0];
	obj.style.height = $(obj)
		.children("iframe")
		.contents()
		.find("body")
		.css("height");
	obj.style.width = $(obj)
		.children("iframe")
		.contents()
		.find("body")
		.css("width");
}

function changeWin() {
	let img = $("#main-img")[0];
	let title = $("#title-text")[0];

	if (img.src.includes("N1.png")) {
		img.src = "/images/N2.png";
		title.text = "@meloettium";
		title.href =
			"https://meloettium.tumblr.com/post/700943559813152768/finersun-the-gift-of-stormdancer-edit-this-is";
	} else if (img.src.includes("N2.png")) {
		img.src = "/images/N3.png";
		title.text = "@mxthrklef";
		title.href =
			"https://www.tumblr.com/mxthrklef/735905421180780544/redraw-from-da-gaeme";
	} else if (img.src.includes("N3.png")) {
		img.src = "/images/N4.png";
		title.text = "@onionowt";
		title.href =
			"https://onionowt.tumblr.com/post/738787270558138368/redraw-of-an-old-art-im-talking-about-this-one";
	} else if (img.src.includes("N4.png")) {
		img.src = "/images/N6.png";
		title.text = "@10domu08";
		title.href = "https://10domu08.tumblr.com/post/189451479839";
	} else if (img.src.includes("N6.png")) {
		img.src = "/images/N7.png";
		title.text = "@genlirema";
		title.href = "https://genlirema.tumblr.com/post/737985721314476033";
	} else if (img.src.includes("N7.png")) {
		img.src = "/images/N8.png";
		title.text = "@touyarokii";
		title.href = "https://twitter.com/Touyarokii/status/1461079978456457218";
	} else if (img.src.includes("N8.png")) {
		img.src = "/images/N9.png";
		title.text = "@snapling";
		title.href =
			"https://www.tumblr.com/snapling/740441175361830912/n-and-reshiram-doodle-i-did-a-little-bit-back-i";
	} else if (img.src.includes("N9.png")) {
		img.src = "/images/N1.png";
		title.text = "@nanomias";
		title.href =
			"https://www.tumblr.com/nanomias/739364566303178752/n-harmonia";
	}
	setTimeout(resizeIframeDefault, 100);
}

$(document).ready(() => {
	insertWindow("abtme");
	insertWindow("clock");
	insertWindow("pictures");
	setTimeout(() => {
		$(".abtme-win").css("left", "60vw");
		$(".abtme-win").css("top", "10vh");
		$(".clock-win").css("left", "15vw");
		$(".clock-win").css("top", "15vh");
		$(".pictures-win").css("left", "40vw");
		$(".pictures-win").css("top", "40vh");
	}, 200);
});
