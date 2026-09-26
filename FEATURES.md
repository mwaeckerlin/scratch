# Features

Numbered register of every feature; a number is never reused. Every feature is covered by tests listed in [TESTS.md](TESTS.md); the guard `tests/docs-contract.sh` fails when a feature has no test.

- **F1 — Unprivileged users.** The run user `somebody` and the build user `coder` exist with their home directories; the image switches to `somebody`, so every derived image starts non-root.
- **F2 — Shared group.** The group `shared-access` with the fixed id 500 contains `somebody`, for data shared on volumes between containers.
- **F3 — Variables for derived images.** `RUN_USER`, `RUN_GROUP`, `RUN_HOME`, `BUILD_USER`, `BUILD_GROUP`, `BUILD_HOME`, `SHARED_GROUP_NAME`, `SHARED_GROUP_ID` name the users and groups; `PKG_INSTALL`, `PKG_REMOVE`, `PKG_SEARCH`, `PKG_CLEANUP1`, `PKG_CLEANUP2`, `ALLOW_USER`, `ALLOW_BUILD` are the commands a Dockerfile uses instead of hard coding them.
- **F4 — Language.** `LANG` defaults to `en_US.UTF-8`; a derived image sets another one with the build argument `lang`.
- **F5 — Prompt.** `PS1` is a coloured prompt that shows the container name from `CONTAINERNAME`.
- **F6 — Headless.** The image contains no shell, no busybox and no scripting language, so an attacker who reaches code execution finds no tool to pivot with.
- **F7 — Published for amd64 and arm64.** Every push builds the image natively for both architectures, tests it with `npm test`, deploys it with `npm run deploy` under an architecture tag and joins the architectures under one tag on Docker Hub, only when every step on every architecture succeeded; every image repository of the family uses the same reusable workflow of this repository, which publishes exactly the images its compose file builds.
- **F8 — Tags by date and version.** Every image is published under its tag, the date of the build, and with a version in `package.json` the version with and without the date (`latest`, `20260926`, `1.3.2`, `1.3.2-20260926`; `inotify`, `inotify-20260926`, `inotify-1.3.2`, `inotify-1.3.2-20260926`), so every rebuild stays addressable.
- **F9 — Version branches.** A repository names its version branches with rules that append a suffix to every tag (`new-33` → `nginx-33`, …); every push to such a branch builds its version, and the weekly run of the default branch starts all of them, so every version gets the updates.
