import lunar from "../.lunar/workers/src/worker.mjs";
import { proxyInstaller } from "./install.mjs";

export default {
	fetch(request, env, ctx) {
		if (new URL(request.url).pathname === "/install.sh") {
			return proxyInstaller(request, ctx, caches.default);
		}
		return lunar.fetch(request, env, ctx);
	},
};
