interface Revision {
	generation: number;
	session: string;
}

function revision(value: unknown): value is Revision {
	if (typeof value !== "object" || value === null) return false;
	return (
		"generation" in value &&
		typeof value.generation === "number" &&
		Number.isFinite(value.generation) &&
		"session" in value &&
		typeof value.session === "string"
	);
}

const raw: unknown = JSON.parse(
	document.getElementById("lunar-reload-data")?.textContent ?? "null",
);
if (revision(raw)) {
	const initial = raw;
	let pending = false;
	setInterval(async () => {
		if (pending) return;
		pending = true;
		try {
			const response = await fetch("/_lunar/dev", { cache: "no-store" });
			if (!response.ok) return;
			const next: unknown = await response.json();
			if (
				revision(next) &&
				(next.generation !== initial.generation || next.session !== initial.session)
			) {
				location.reload();
			}
		} catch {
		} finally {
			pending = false;
		}
	}, 800);
}
