const MODDIR = "/data/adb/modules/noopt-demo";
const CONFIGDIR = "/data/adb/noopt";

function openExternal(url) {
	try {
		execShell(`am start -a android.intent.action.VIEW -d ${shellQuote(url)}`);
	} catch (_) {
		window.open(url, "_blank");
	}
}

const DEFAULT_TARGET_PATHS = [
	"/dev/cpuset/AppOpt",
	"/data/system/junge",
	"/dev/cpuset/scene-daemon",
	"/dev/scene",
];
const DEFAULT_DENY_PACKAGES = [
	"com.chunqiunativecheck",
	"com.eltavine.duckdetector",
	"luna.safe.luna",
];
const files = {
	targets: `${CONFIGDIR}/target_path.conf`,
	hideDirents: `${CONFIGDIR}/hide_dirents.conf`,
	scope: `${CONFIGDIR}/scope_mode.conf`,
	denyPackages: `${CONFIGDIR}/deny_packages.conf`,
	denyUids: `${CONFIGDIR}/deny_uids.conf`,
	service: `${MODDIR}/service.sh`,
};

let apps = [];
let selectedPackages = new Set();
let busy = false;

const $ = (selector) => document.querySelector(selector);
const pathList = $("#pathList");
const appList = $("#appList");
const statusText = $("#statusText");
const toast = $("#toast");
const actionButtons = [
	$("#refreshBtn"),
	$("#loadAppsBtn"),
	$("#saveBtn"),
	$("#reloadBtn"),
	$("#addPathBtn"),
];

function shellQuote(value) {
	return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function getKsuBridge() {
	if (typeof window !== "undefined" && window.ksu?.exec) {
		return window.ksu;
	}

	if (typeof ksu !== "undefined" && ksu?.exec) {
		return ksu;
	}

	return null;
}

function execShell(command) {
	const bridge = getKsuBridge();
	if (!bridge) {
		throw new Error("KernelSU bridge is not available");
	}

	return new Promise((resolve, reject) => {
		const callbackName = `noopt_exec_${Date.now()}_${Math.random().toString(16).slice(2)}`;

		window[callbackName] = (errno, stdout, stderr) => {
			delete window[callbackName];
			if (errno && errno !== 0) {
				reject(new Error(stderr || stdout || `Command failed: ${errno}`));
				return;
			}
			resolve(stdout || "");
		};

		try {
			bridge.exec(command, JSON.stringify({}), callbackName);
		} catch (error) {
			try {
				bridge.exec(command, callbackName);
			} catch (fallbackError) {
				delete window[callbackName];
				reject(fallbackError);
				return;
			}
		}
	});
}

function showToast(message) {
	toast.textContent = message;
	toast.hidden = false;
	clearTimeout(showToast.timer);
	showToast.timer = setTimeout(() => {
		toast.hidden = true;
	}, 4200);
}

function setBusy(nextBusy, message) {
	busy = nextBusy;
	for (const button of actionButtons) {
		if (button) button.disabled = nextBusy;
	}
	if (message) statusText.textContent = message;
}

async function runAction(message, action) {
	if (busy) {
		showToast("正在处理，请稍等");
		return;
	}

	setBusy(true, message);
	try {
		await action();
	} catch (error) {
		showToast(error.message);
		throw error;
	} finally {
		setBusy(false);
	}
}

async function readFile(path) {
	return execShell(`[ -f ${shellQuote(path)} ] && cat ${shellQuote(path)} || true`);
}

async function writeLines(path, lines) {
	const clean = lines.map((line) => line.trim()).filter(Boolean);
	const body = clean.length
		? `printf '%s\\n' ${clean.map(shellQuote).join(" ")} > ${shellQuote(path)}`
		: `: > ${shellQuote(path)}`;
	await execShell(`mkdir -p ${shellQuote(CONFIGDIR)}; chmod 0700 ${shellQuote(CONFIGDIR)} 2>/dev/null || true; ${body}`);
}

function linesFromText(text) {
	return text.split(/\r?\n/)
		.map((line) => line.trim())
		.filter((line) => line && !line.startsWith("#"));
}

function renderPaths(paths) {
	pathList.textContent = "";
	const list = paths.length ? paths : DEFAULT_TARGET_PATHS;
	for (const path of list) {
		const row = document.createElement("div");
		row.className = "pathRow";
		const input = document.createElement("input");
		input.type = "text";
		input.value = path;
		const remove = document.createElement("button");
		remove.type = "button";
		remove.textContent = "删";
		remove.addEventListener("click", () => {
			row.remove();
		});
		row.append(input, remove);
		pathList.append(row);
	}
}

function collectPaths() {
	return [...pathList.querySelectorAll("input")]
		.map((input) => input.value.trim())
		.filter(Boolean);
}

function parsePackageLine(line) {
	const match = line.match(/^package:(.+?)\s+uid:(\d+)$/);
	if (!match) return null;
	return { pkg: match[1], uid: match[2] };
}

function renderApps() {
	const query = $("#searchInput").value.trim().toLowerCase();
	appList.textContent = "";

	const filtered = apps.filter((app) => !query || app.pkg.toLowerCase().includes(query));
	for (const app of filtered) {
		const row = document.createElement("label");
		row.className = "appRow";

		const checkbox = document.createElement("input");
		checkbox.type = "checkbox";
		checkbox.checked = selectedPackages.has(app.pkg);
		checkbox.addEventListener("change", () => {
			if (checkbox.checked) selectedPackages.add(app.pkg);
			else selectedPackages.delete(app.pkg);
		});

		const pkg = document.createElement("div");
		pkg.className = "pkg";
		pkg.textContent = app.pkg;

		const uid = document.createElement("div");
		uid.className = "uid";
		uid.textContent = app.uid;

		row.append(checkbox, pkg, uid);
		appList.append(row);
	}
}

async function loadApps() {
	statusText.textContent = "正在加载应用...";
	const showSystem = $("#showSystemInput").checked;
	const command = showSystem ? "pm list packages -U" : "pm list packages -U -3";
	const output = await execShell(command);
	apps = output.split(/\r?\n/)
		.map(parsePackageLine)
		.filter(Boolean)
		.sort((a, b) => a.pkg.localeCompare(b.pkg));
	renderApps();
	showToast(`已加载 ${apps.length} 个应用`);
}

async function refreshConfig() {
	statusText.textContent = "正在刷新...";
	const targetText = await readFile(files.targets);
	const hideText = await readFile(files.hideDirents);
	const scopeText = await readFile(files.scope);
	const pkgText = await readFile(files.denyPackages);
	const uidText = await readFile(files.denyUids);
	const procText = await execShell("grep '^noopt ' /proc/modules || true");

	renderPaths(linesFromText(targetText));
	$("#hideDirentsInput").checked = (hideText.trim() || "1") !== "0";
	const scope = (scopeText.trim() || "deny") === "global" ? "global" : "deny";
	document.querySelector(`input[name="scope"][value="${scope}"]`).checked = true;
	const packageLines = linesFromText(pkgText);
	selectedPackages = new Set(packageLines.length ? packageLines : DEFAULT_DENY_PACKAGES);
	$("#denyUidsInput").value = linesFromText(uidText).join("\n");
	statusText.textContent = procText.trim() ? "模块已加载" : "模块未加载";
	renderApps();
}

async function saveConfig() {
	statusText.textContent = "正在保存...";
	const scope = document.querySelector('input[name="scope"]:checked')?.value || "global";
	await writeLines(files.targets, collectPaths());
	await writeLines(files.hideDirents, [$("#hideDirentsInput").checked ? "1" : "0"]);
	await writeLines(files.scope, [scope]);
	await writeLines(files.denyPackages, [...selectedPackages].sort());
	await writeLines(files.denyUids, linesFromText($("#denyUidsInput").value));
	statusText.textContent = "已保存";
	showToast("已保存");
}

async function reloadModule() {
	await saveConfig();
	statusText.textContent = "正在重载...";
	await execShell(
		`if grep -q '^noopt ' /proc/modules 2>/dev/null; then rmmod noopt; fi; NOOPT_TARGET_WAIT_SECONDS=5 NOOPT_PACKAGE_WAIT_SECONDS=5 sh ${shellQuote(files.service)}; dmesg | grep noopt | tail -n 20`
	);
	await refreshConfig();
	showToast("模块已重载");
}

$("#addPathBtn").addEventListener("click", () => {
	const row = document.createElement("div");
	row.className = "pathRow";
	const input = document.createElement("input");
	input.type = "text";
	input.placeholder = "/system/app/example";
	const remove = document.createElement("button");
	remove.type = "button";
	remove.textContent = "删";
	remove.addEventListener("click", () => row.remove());
	row.append(input, remove);
	pathList.append(row);
	input.focus();
});

$("#loadAppsBtn").addEventListener("click", () => runAction("正在加载应用...", loadApps).catch(() => {}));
$("#refreshBtn").addEventListener("click", () => runAction("正在刷新...", refreshConfig).catch(() => {}));
$("#searchInput").addEventListener("input", renderApps);
$("#saveBtn").addEventListener("click", () => runAction("正在保存...", saveConfig).catch(() => {}));
$("#reloadBtn").addEventListener("click", () => runAction("正在重载...", reloadModule).catch((error) => {
	statusText.textContent = "重载失败";
	showToast(error.message || "重载失败");
}));

for (const radio of document.querySelectorAll('input[name="scope"]')) {
	radio.addEventListener("change", () => {
		if (radio.value === "deny" && radio.checked && apps.length === 0) {
			loadApps().catch(() => {});
		}
	});
}

runAction("正在读取配置...", refreshConfig).catch((error) => {
	statusText.textContent = "读取失败";
	showToast(error.message);
});
