// minimize window when minimize button pressed
$(":button[aria-label='Minimize']").on("click", (e) => {
	$(e.target).parents(".window").children("[class!='title-bar']").toggle();
});

// close window when close button pressed. Uses terniary operator for when
// the URL contains ".html" (i.e. when debugging locally) and adjusts accordingly
$(":button[aria-label='Close']").on("click", (e) => {
	let ifr =
		e.target.formAction.indexOf(".html") == -1
			? $(parent.document).find(
					"#" +
						e.target.formAction.slice(e.target.formAction.lastIndexOf("/") + 1),
				)
			: $(parent.document).find(
					"#" +
						e.target.formAction.slice(
							e.target.formAction.lastIndexOf("/") + 1,
							-5,
						),
				);
		$(ifr).remove();
});

// maximize window when maximize button pressed
$(":button[aria-label='Maximize']").on("click", (e) => {
	let win = $(e.target).parents(".window");
	// console.log(win.css("width"));
	if (win.get(0).style.minWidth == "300px") {
		win.css("min-width", "100vh");
	} else {
		win.css("min-width", "300px");
	}
	setTimeout(resizeIframeDefault, 100);
});

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

function resizeIframe(obj) {
	console.log($(obj).contents().find("body").css("width"));
	obj.style.height = $(obj).contents().find("body").css("height");
	obj.style.width = $(obj).contents().find("body").css("width");
}

function resizeIframeDefault() {
	let obj = window.parent.$("#pictures")[0];
	// console.log($(obj).contents().find("body").css("width"));
	obj.style.height = $(obj).contents().find("body").css("height");
	obj.style.width = $(obj).contents().find("body").css("width");
}
