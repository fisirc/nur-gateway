## Thwomp

<img src="./docs/media/thwomp.webp" alt="super mario thwomp"
align="right" width="200" />

API gateway service of the Nur project, low-dependencies and
linux-only! :3c

### BUILDING

You will need a working zig compiler to compile this project (at least
v0.14.0). Then release builds (without debuginfo and nonverbose) are
built like this:

```sh
zig build -Doptimize=ReleaseSafe
```

Debug builds are built like this:

```sh
zig build -Doptimize=ReleaseSafe
```

### CONFIGURATION

Some runtime parameters can be set through an `.env` file:

```
PG_URL="<postgres-uri>"
SV_PORT="<desired-port>"
SV_HOSTNAME="<desired-hostname>"
```

### INNERS

This service exposes an HTTP server through the port specified at
[CONFIGURATION](### CONFIGURATION), then intercepts every request's
headers to capture the target. Once it has found the function
information related to that target it forwards the whole request to a
worker service.

The target should be formatted as follows:

```
/<project-id>/some/path
```


