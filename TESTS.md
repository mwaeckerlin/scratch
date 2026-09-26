# Tests

Register of all tests, sorted by the [FEATURES.md](FEATURES.md) number each test covers. `npm test` runs everything; the guard `tests/docs-contract.sh` fails when a feature has no test entry here.

## Image contract

- **F1** `tests/config-contract.sh` › runs_as_somebody, passwd_somebody, passwd_coder, home_somebody, home_coder — both users and their homes exist, the image runs as `somebody`.
- **F2** `tests/config-contract.sh` › shared_group_500_with_somebody — group `shared-access` has id 500 and contains `somebody`.
- **F3** `tests/config-contract.sh` › env_RUN_USER … env_ALLOW_BUILD — every variable has its documented value.
- **F4** `tests/config-contract.sh` › env_LANG, child_lang_build_arg — the default language, and a child image built with `--build-arg lang=de_CH.UTF-8` carries it.
- **F5** `tests/config-contract.sh` › env_PS1_shows_container — the prompt shows the container name.
- **F6** `tests/image-contract.sh` › no sh, no bash, no busybox, no perl — the image is headless.

## Workflow contract

- **F7** `tests/workflow-contract.sh` › tags_without_version, same_image_once, no_image_name_skipped, submodule_skipped, nothing_own_fails, arch_step_tags_and_runs_deploy, deploy_step_joins_into_every_tag, no_job_asks_for_its_own_rights — the reusable workflow selects exactly the images a repository publishes, the override makes `docker compose push` use the architecture tags, and the deploy joins the architectures into every tag; no job asks for rights of its own, so a repository whose token may only read starts the workflow.
- **F8** `tests/workflow-contract.sh` › tags_without_version, tags_with_version — date, version and version with date, for `latest` and for an own tag.
- **F9** `tests/workflow-contract.sh` › version_branch_gets_its_suffix, main_version_branch_without_suffix, unnamed_branch_without_suffix, latest_on_a_branch_becomes_the_suffix, weekly_run_starts_every_version_branch — the suffix of a version branch, no suffix elsewhere, and the weekly run starting every version branch and no other.
