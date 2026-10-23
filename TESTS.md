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

- **F7** `tests/workflow-contract.sh` › tags_without_version, same_image_once, no_image_name_skipped, submodule_skipped, nothing_own_fails, arch_step_tags_and_runs_deploy, deploy_step_joins_into_every_tag, no_job_asks_for_its_own_rights, build_checkout_includes_submodules — the reusable workflow selects exactly the images a repository publishes, the override makes `docker compose push` use the architecture tags, and the deploy joins the architectures into every tag; no job asks for rights of its own, so a repository whose token may only read starts the workflow; the build checks out the submodules a test may build from.
- **F8** `tests/workflow-contract.sh` › tags_without_version, tags_with_version — date, version and version with date, for `latest` and for an own tag.
- **F9** `tests/workflow-contract.sh` › version_branch_gets_its_suffix, main_version_branch_without_suffix, unnamed_branch_without_suffix, latest_on_a_branch_becomes_the_suffix, scheduled_run_starts_every_version_branch — the suffix of a version branch, no suffix elsewhere, and the scheduled run starting every version branch and no other.
- **F11** `tests/workflow-contract.sh` › replaced_image_keeps_its_build_day — the image that carried a tag gets the tag with its build day, for a single-platform and a multi-platform image, and no second one where the dated tag exists or the new build writes it.
- **F10** `tests/workflow-contract.sh` › git_tag_is_the_version, branch_rule_prefixes_its_version, git_tag_without_rule_fails, arch_step_pushes_without_deploy_script, scheduled_run_starts_every_release_tag — a git tag gets the suffix of its `tag` rule and no version of `package.json`, a branch rule puts its `version` prefix before the version (`app-2-v2.1.0`), a git tag without rule fails the run, a git tag without `deploy` script is pushed with `docker compose push`, and the scheduled run starts every git tag a rule names.

- **F13** `tests/workflow-contract.sh` › keep_alive_runs_on_schedule, keep_alive_enables_the_calling_workflow, keep_alive_without_rights_warns — the scheduled run calls the enable endpoint for the workflow file of the caller, and a refused call leaves a warning without failing the run.

## Check contract

- **F12** `tests/check-contract.sh` › the_check_runs_before_the_build, check_and_build_select_the_same_images — the build waits for the check and starts only on its decision, and both jobs select the same images.
- **F12** `tests/check-contract.sh` › scheduled_run_without_published_image_builds, image_without_record_builds — against a real registry, an image that is not published, or was published without the labels of its sources, builds.
- **F12** `tests/check-contract.sh` › record_names_parents_and_downloads — the record names the parent from a global `ARG` and the one from another Dockerfile under one name, leaves out stages, `scratch`, the images of the compose file and the address assembled in shell code, and names the download by its `ETag` and the release by its redirect.
- **F12** `tests/check-contract.sh` › unchanged_sources_do_not_build, built_image_does_not_build_again, start_by_the_scheduled_run_checks — unchanged sources do not build, also not after a rebuild, and a start by the scheduled run checks as well; a release asset that answers with another `ETag` every time causes no build.
- **F12** `tests/check-contract.sh` › lookups_stay_within_the_pull_budget — the registry log counts at most one manifest GET per parent and three per published image the check looks up.
- **F12** `tests/check-contract.sh` › changed_download_builds, new_release_builds, changed_parent_builds — a new `ETag`, a new release and a new parent digest each build and name the source.
- **F12** `tests/check-contract.sh` › image_older_than_rebuild_days_builds, rebuild_days_sets_the_age — an image eight days old builds with the default, and does not with `rebuild-days` 9.
- **F12** `tests/check-contract.sh` › push_always_builds, manual_start_always_builds — a push and a manual start build without a comparison.
- **F12** `tests/check-contract.sh` › record_round_trip_through_the_labels — the record of the check reaches the labels of every published image through the real steps that label, build, push and join.
- **F12** `tests/check-contract.sh` › failed_lookup_fails_the_check — a parent that cannot be looked up fails the run with the registry's error.
