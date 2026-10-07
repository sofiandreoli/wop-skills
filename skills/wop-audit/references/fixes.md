# Mechanical fixes

Only substitutions belong here: a literal becomes a value read from the environment, with the old
literal kept as the default so running the app the way people run it today still works.

**The one exception is a literal that is itself the collision.** A fixed `/tmp/myapp.pid` cannot stay as
the fallback, because the shared path is the whole problem — keeping it would leave the bug in place for
anyone not setting the variable. Where a fix has to change the default, it is called out below, and the
change goes in the report rather than passing silently as a substitution.

Every fix is one diff, shown before it is applied, approved on its own. Anything not in this file
goes in the report instead.

---

## Literal listen port → environment

Keep the old number as the default. Nobody's existing workflow should break.

**Node / Express**

```diff
-app.listen(3000)
+app.listen(process.env.PORT || 3000)
```

**Go**

```diff
-http.ListenAndServe(":8080", mux)
+port := os.Getenv("PORT")
+if port == "" {
+	port = "8080"
+}
+http.ListenAndServe(":"+port, mux)
```

**Python / uvicorn, Django**

```diff
-uvicorn.run(app, port=8000)
+uvicorn.run(app, port=int(os.environ.get("PORT", 8000)))
```

**Rails / Puma** — `config/puma.rb`

```diff
-port 3000
+port ENV.fetch("PORT", 3000)
```

**Vite / Next** — prefer leaving the config alone and letting `cmd` pass the port in
`.devmanager.yml` (`npm run dev -- --port $PORT`). Only edit the config when it pins a port that the
flag cannot override.

**A port inside a `Procfile` or an npm script** is the same substitution, in shell form:

```diff
-worker: bundle exec sidekiq -p 3100
+worker: bundle exec sidekiq -p ${WORKER_PORT:-3100}
```

```diff
-"dev": "vite --port 5173"
+"dev": "vite --port ${PORT:-5173}"
```

## Fixed pidfile, socket or tmp path → environment

Two worktrees both claim a fixed path, and the second one wins silently.

```diff
-PIDFILE = "/tmp/myapp.pid"
+PIDFILE = ENV.fetch("PIDFILE") { File.join(Dir.pwd, "tmp", "myapp.pid") }
```

`.devmanager.yml` then sets `PIDFILE: "{worktree_path}/tmp/myapp.pid"`, which is distinct per branch.
Pair it with a `mkdir -p tmp` in `after_create`, since an empty directory does not exist in a fresh
worktree.

**This one changes the default**, from `/tmp/myapp.pid` to a path under the working directory — the
exception noted at the top, since a shared `/tmp` path is the collision itself. Say so when proposing it:
anyone running the app without `PIDFILE` set gets the new location.

## Literal client URL → environment

```diff
-const API = "http://localhost:3000/api"
+const API = import.meta.env.VITE_API_URL ?? "http://localhost:3000/api"
```

Then `.devmanager.yml` wires it with `VITE_API_URL: "http://localhost:{backend_port}/api"`. Name the
variable the way the framework requires it to be exposed: `VITE_` for Vite, `NEXT_PUBLIC_` for Next,
`REACT_APP_` for Create React App.

## Literal database name or URL → environment

**Rails** — `config/database.yml`

```diff
 development:
   <<: *default
-  database: myapp_development
+  database: <%= ENV.fetch("DB_NAME", "myapp_development") %>
```

When the app uses a full URL instead, prefer `url: <%= ENV["DATABASE_URL"] %>`, which Rails already
honours without any edit — check whether a fix is needed at all before proposing one.

**Django** — `settings.py`

```diff
-        "NAME": "myapp",
+        "NAME": os.environ.get("DB_NAME", "myapp"),
```

**Prisma** — `prisma/schema.prisma`

```diff
-  url = "postgresql://localhost:5432/myapp"
+  url = env("DATABASE_URL")
```

Prisma takes no inline default, so this one *requires* `DATABASE_URL` to be set. Say that out loud:
after the fix, running the app outside `wop` needs the variable in the developer's own `.env`.

**Knex** — `knexfile.js`

```diff
-      database: "myapp_dev",
+      database: process.env.DB_NAME || "myapp_dev",
```

## Tracked `.env` → ignored

Two steps, and the second one is the one people forget:

```bash
printf '\n.env\n' >> .gitignore
git rm --cached .env
```

`git rm --cached` keeps the file on disk and stops tracking it. Before running it, say clearly that
the file stays locally but **disappears from every fresh clone and every worktree**, so whatever it
holds must be reproducible — usually by committing a `.env.example` in the same commit. If the file
contains live secrets, note that removing it from the index does not remove it from history.

## Absolute path → repo-relative

```diff
-DATA_DIR = "/Users/sofia/projects/myapp/data"
+DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
```

In Ruby:

```diff
-UPLOADS = "/Users/sofia/projects/myapp/uploads"
+UPLOADS = File.expand_path("uploads", __dir__)
```

In shell scripts:

```diff
-cd ~/projects/myapp
+cd "$(dirname "$0")/.."
```

## Compose host port and container name → parameterised

```diff
 services:
   db:
-    container_name: myapp_db
+    container_name: ${COMPOSE_PROJECT_NAME:-myapp}_db
     ports:
-      - "5432:5432"
+      - "${DB_HOST_PORT:-5432}:5432"
```

Usually the right answer is **not to apply this**. One shared server with a database per branch is what
`wop`'s `databases` block gives you, and it is the model `wop` is built around; a database container per
worktree is the worse trade. Offer this fix only when the compose service really must be per-worktree.

When you leave it alone, record the finding as **red by design** rather than as an outstanding red —
otherwise every re-run reports the same unfixable blocker and the report never converges.

## Redis keys → prefixed

Not mechanical in general, so it is usually a report item. It qualifies as a fix only when the app
already funnels every key through one helper:

```diff
-def key(name) = name
+def key(name) = [ENV.fetch("REDIS_PREFIX", ""), name].reject(&:empty?).join(":")
```

Then `.devmanager.yml` sets `REDIS_PREFIX: "{db_name_cache}"`, which is the exact prefix `wop down`
deletes. If keys are built inline all over the codebase, report it and move on.
