let audios = [
	"11%20-%20N%27s%20Castle",
	"12%20-%20N%27s%20Room",
	"13%20-%20N%27s%20Theme",
	"14%20-%20Battle!%20(N)",
];
let intervalID;

$("audio").on("loadedmetadata", () => {
	let jukebox = $("audio")[0];
	let totTime =
		("0" + Math.floor(Math.round(jukebox.duration) / 60)).slice(-2) +
		":" +
		("0" + (Math.round(jukebox.duration) % 60)).slice(-2);
	$(".total-time").text(totTime);
	$(".song-bar").attr("max", Math.round(jukebox.duration));
	$(".song-name").text(
		jukebox.currentSrc
			.slice(jukebox.currentSrc.lastIndexOf("/") + 1, -4)
			.replace(/%20/g, " ")
			.replace(/%27/g, ""),
	);
});

$("audio").on("ended", async () => {
	let jukebox = $("audio")[0];
	clearInterval(intervalID);
	next(jukebox);
	$(".current-time").text("00:00");
	$(".song-bar").attr("value", 0);
	intervalID = setInterval(everySecond, 1000);
});

$("button#back").on("click", async () => {
	let jukebox = $("audio")[0];
	clearInterval(intervalID);
	prev(jukebox);
	intervalID = setInterval(everySecond, 1000);
});

$("button#playpause").on("click", async () => {
	let jukebox = $("audio")[0];
	if (jukebox.paused) {
		intervalID = setInterval(everySecond, 1000);
		await playAudio(jukebox);
	} else {
		clearInterval(intervalID);
		jukebox.pause();
	}
});

$("button#next").on("click", () => {
	let jukebox = $("audio")[0];
	clearInterval(intervalID);
	next(jukebox);
	intervalID = setInterval(everySecond, 1000);
});

async function everySecond() {
	let jukebox = $("audio")[0];
	let pastMin = parseInt($(".current-time").text().slice(0, 2));
	let pastSec = parseInt($(".current-time").text().slice(3, 5));
	let currMin = ("0" + (pastMin + (pastSec == 59 ? 1 : 0))).slice(-2);
	let currSec = ("0" + ((pastSec % 60) + 1)).slice(-2);
	$(".current-time").text(currMin + ":" + currSec);
	$(".song-bar").attr("value", Math.round(jukebox.currentTime));
}

async function next(jukebox) {
	let nextIndex =
		audios.indexOf(
			jukebox.currentSrc.slice(jukebox.currentSrc.lastIndexOf("/") + 1, -4),
		) + 1;
	if (nextIndex == audios.length) {
		nextIndex = 0;
	}
	$(".current-time").text("00:00");
	$(".song-bar").attr("value", 0);
	jukebox.src = `https://crowconclave.dev/${audios[nextIndex]}.mp3`; // change the song
	jukebox.fastSeek(0); // seek to begining
	await playAudio(jukebox);
}

async function prev(jukebox) {
	// if the current time > 10s, restart the song
	if (jukebox.currentTime > 10) {
		jukebox.fastSeek(0); // seek to begining
		$(".current-time").text("00:00");
		$(".song-bar").attr("value", 0);
		return;
	}

	// get the index of the previous song
	let prevIndex =
		audios.indexOf(
			jukebox.currentSrc.slice(jukebox.currentSrc.lastIndexOf("/") + 1, -4),
		) - 1;
	if (prevIndex == -1) {
		prevIndex = audios.length - 1;
	}
	$(".current-time").text("00:00");
	$(".song-bar").attr("value", 0);

	jukebox.src = `https://crowconclave.dev/${audios[prevIndex]}.mp3`; // change the song
	jukebox.fastSeek(0); // seek to begining
	await playAudio(jukebox);
}

function playAudio(audio) {
	return new Promise((res) => {
		audio.play();
		audio.onended = res;
	});
}
// <source src="/music/NsCastle.mp3" type="audio/mp3">
// <source src="/music/NsRoom.mp3" type="audio/mp3">
// <source src="/music/NsTheme.mp3" type="audio/mp3">
// <source src="/music/BattleN.mp3" type="audio/mp3">
