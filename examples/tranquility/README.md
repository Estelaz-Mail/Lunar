# tranquility

The example app, named after the sea the first landing was in. It is also a
test fixture: `spec/site_spec.lua` serves requests against this directory, so
every feature demonstrated here is a feature with a test behind it.

```sh
bin/lunar dev examples/tranquility   # http://localhost:3000
bin/lunar map examples/tranquility   # the route table as discovered
```

What it shows:

| Where                       | What                                               |
| --------------------------- | --------------------------------------------------- |
| `orbit/shell.lunar`         | a shell with a `<slot />`, and state of its own     |
| `orbit/shell.lua`           | a probe that runs for every page inside it          |
| `orbit/page.lunar`          | state, `derived`, a binding, an imported component  |
| `orbit/blog/page.lua`       | a probe that reads out of `lib/`                    |
| `orbit/blog/[slug]/`        | a dynamic segment, and `event.fail(404, …)`         |
| `orbit/api/time/api.lua`    | an endpoint with GET and POST                       |
| `orbit/eclipse.lunar`       | what a failure renders                              |
| `app.html`                  | a document shell of the app's own                   |
