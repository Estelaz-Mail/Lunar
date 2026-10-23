const UPSTREAM = "https://raw.githubusercontent.com/Glazastyy/Lunar/refs/heads/main/install.sh";

function failure(status, message, headers = {}) {
	return new Response(message, {
		status,
		headers: {
			"Content-Type": "text/plain; charset=utf-8",
			"Cache-Control": "no-store",
			"X-Content-Type-Options": "nosniff",
			...headers,
		},
	});
}

export async function proxyInstaller(request, ctx, cache, fetchUpstream = fetch) {
	if (request.method !== "GET" && request.method !== "HEAD") {
		return failure(405, "Method not allowed\n", { Allow: "GET, HEAD" });
	}

	// Query strings and client headers must not fragment the shared script cache.
	const key = new Request(new URL("/install.sh", request.url), {
		method: "GET",
	});
	let response;
	try {
		response = await cache.match(key);
	} catch (error) {
		console.error("install: cache read failed", error);
	}
	const hit = Boolean(response);

	if (!response) {
		let upstream;
		try {
			upstream = await fetchUpstream(UPSTREAM, {
				method: "GET",
				redirect: "manual",
				signal: AbortSignal.timeout(10_000),
			});
		} catch (error) {
			console.error("install: upstream unavailable", error);
			return failure(502, request.method === "HEAD" ? null : "Installer temporarily unavailable\n");
		}
		if (upstream.status !== 200) {
			if (upstream.body) await upstream.body.cancel();
			return failure(502, request.method === "HEAD" ? null : "Installer temporarily unavailable\n");
		}

		const headers = new Headers({
			"Content-Type": "text/plain; charset=utf-8",
			"Cache-Control": "public, max-age=300",
			"X-Content-Type-Options": "nosniff",
		});
		for (const name of ["ETag", "Last-Modified"]) {
			if (upstream.headers.has(name)) headers.set(name, upstream.headers.get(name));
		}
		response = new Response(upstream.body, { headers });
		ctx.waitUntil(
			cache.put(key, request.method === "HEAD" ? response : response.clone()).catch((error) => {
				console.error("install: cache write failed", error);
			}),
		);
	}

	const headers = new Headers(response.headers);
	headers.set("X-Cache", hit ? "HIT" : "MISS");
	if (request.method === "HEAD") {
		if (hit && response.body) ctx.waitUntil(response.body.cancel());
		return new Response(null, { headers });
	}
	return new Response(response.body, { headers });
}
