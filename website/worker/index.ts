import lunar, { type WorkerEnv, type WorkerContext } from "../.lunar/workers/src/worker.ts";
import { proxyInstaller } from "./install.ts";

export default {
	fetch(request: Request, env: WorkerEnv, ctx: WorkerContext): Promise<Response> {
		if (new URL(request.url).pathname === "/install.sh") {
			return proxyInstaller(request, ctx, caches.default);
		}
		return lunar.fetch(request, env, ctx);
	},
};
