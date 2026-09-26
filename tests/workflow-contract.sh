#!/usr/bin/env bash
# Workflow contract: the reusable workflow .github/workflows/docker-image.yml
# selects exactly the images a repository publishes, under exactly its tags.
#
# The selection step is taken out of the workflow file and run against small
# compose projects, so the test measures the code that GitHub runs:
# - a service with `build` and `image` is published, an untagged image as
#   `latest`, a tagged one under its tag
# - every image also gets the date of the build, and with a version in
#   package.json the version and the version with the date
# - a branch named by a rule of `branch-tags` appends its suffix to every tag
# - two services with the same image publish it once
# - a service without `build` (a foreign image) is not published
# - a service without `image` cannot be pushed and is skipped
# - a service built in a git submodule is left to the submodule's repository
# - a repository that builds nothing of its own fails the run
# - the override it writes makes `docker compose push` of the selected
#   services (the family's `npm run deploy`) use the architecture tags
# It also checks that the caller of this repository uses the local workflow.
#
# Usage: tests/workflow-contract.sh

set -uo pipefail

cd "$(dirname "$0")/.."

python3 - <<'EOF'
import json, os, subprocess, sys, tempfile, yaml

workflow = yaml.safe_load(open('.github/workflows/docker-image.yml'))
# PyYAML reads the key `on` as the boolean True
assert 'workflow_call' in workflow[True], 'docker-image.yml is not reusable'
select = next(s for s in workflow['jobs']['build']['steps'] if s.get('id') == 'select')['run']

caller = yaml.safe_load(open('.github/workflows/docker.yml'))
assert caller['jobs']['docker']['uses'] == './.github/workflows/docker-image.yml', 'scratch must call its own workflow'

passed = failed = 0


def check(name, compose, services, publish, pushed=None, gitmodules=None, version=None, branch='master', rules=None):
    """Runs the selection step on a compose project and compares the services
    it builds, what it publishes under which tags, and the names compose
    resolves through the override, which are the names `docker compose push`
    uses. `publish` is None where the run must fail."""
    global passed, failed
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, 'docker-compose.yml'), 'w').write(compose)
        for sub in ('sub', 'other'):
            os.makedirs(os.path.join(d, sub))
        if gitmodules:
            open(os.path.join(d, '.gitmodules'), 'w').write(gitmodules)
        if version:
            json.dump({'name': 'x', 'version': version}, open(os.path.join(d, 'package.json'), 'w'))
        output = os.path.join(d, 'github-output')
        env = {**os.environ, 'GITHUB_OUTPUT': output, 'ARCH': 'amd64', 'RUNNER_TEMP': d,
               'REF_NAME': branch, 'BRANCH_TAGS': json.dumps(rules or []), 'BUILD_DATE': '20260926'}
        run = subprocess.run([sys.executable, '-c', select], cwd=d, capture_output=True, text=True, env=env)
        if run.returncode:
            got = None
        else:
            out = dict(l.split('=', 1) for l in open(output).read().splitlines())
            got = {'services': out['services'], 'publish': json.loads(out['publish'])}
            if pushed is not None:
                resolved = subprocess.run(['docker', 'compose', 'config', '--images', *out['services'].split()], cwd=d,
                                          capture_output=True, text=True,
                                          env={**env, 'COMPOSE_FILE': out['compose-files'], 'COMPOSE_PATH_SEPARATOR': ':'})
                got['pushed'] = sorted(set(resolved.stdout.split()))
    expected = None if publish is None else {'services': services, 'publish': publish}
    if expected is not None and pushed is not None:
        expected['pushed'] = pushed
    if got == expected:
        passed += 1
        print(f'  PASS  {name}')
    else:
        failed += 1
        print(f'  FAIL  {name}: expected {expected}, got {got}\n{run.stdout}{run.stderr}')


check('tags_without_version', '''
services:
  plain: {build: ., image: mwaeckerlin/x}
  tagged: {build: {context: ., dockerfile: Dockerfile.inotify}, image: mwaeckerlin/x:inotify}
  foreign: {image: postgres}
''', 'plain tagged', [
    {'source': 'mwaeckerlin/x:latest', 'tags': ['mwaeckerlin/x:latest', 'mwaeckerlin/x:20260926']},
    {'source': 'mwaeckerlin/x:inotify', 'tags': ['mwaeckerlin/x:inotify', 'mwaeckerlin/x:inotify-20260926']},
], pushed=['mwaeckerlin/x:inotify-amd64', 'mwaeckerlin/x:latest-amd64'])

check('tags_with_version', '''
services:
  plain: {build: ., image: mwaeckerlin/x}
  tagged: {build: {context: ., dockerfile: Dockerfile.inotify}, image: mwaeckerlin/x:inotify}
''', 'plain tagged', [
    {'source': 'mwaeckerlin/x:latest', 'tags': ['mwaeckerlin/x:latest', 'mwaeckerlin/x:20260926',
                                               'mwaeckerlin/x:1.3.2', 'mwaeckerlin/x:1.3.2-20260926']},
    {'source': 'mwaeckerlin/x:inotify', 'tags': ['mwaeckerlin/x:inotify', 'mwaeckerlin/x:inotify-20260926',
                                                'mwaeckerlin/x:inotify-1.3.2', 'mwaeckerlin/x:inotify-1.3.2-20260926']},
], version='1.3.2')

NEXTCLOUD_RULES = [{'branch': 'new-([0-9]+)', 'suffix': '-\\1'}, {'branch': 'new', 'suffix': ''}]
NEXTCLOUD = '''
services:
  nginx: {build: ., image: mwaeckerlin/nextcloud:nginx}
'''
check('version_branch_gets_its_suffix', NEXTCLOUD, 'nginx', [
    {'source': 'mwaeckerlin/nextcloud:nginx-33', 'tags': [
        'mwaeckerlin/nextcloud:nginx-33', 'mwaeckerlin/nextcloud:nginx-33-20260926',
        'mwaeckerlin/nextcloud:nginx-33-1.1.2', 'mwaeckerlin/nextcloud:nginx-33-1.1.2-20260926']},
], pushed=['mwaeckerlin/nextcloud:nginx-33-amd64'], version='1.1.2', branch='new-33', rules=NEXTCLOUD_RULES)

check('main_version_branch_without_suffix', NEXTCLOUD, 'nginx', [
    {'source': 'mwaeckerlin/nextcloud:nginx', 'tags': ['mwaeckerlin/nextcloud:nginx', 'mwaeckerlin/nextcloud:nginx-20260926']},
], branch='new', rules=NEXTCLOUD_RULES)

check('unnamed_branch_without_suffix', NEXTCLOUD, 'nginx', [
    {'source': 'mwaeckerlin/nextcloud:nginx', 'tags': ['mwaeckerlin/nextcloud:nginx', 'mwaeckerlin/nextcloud:nginx-20260926']},
], branch='feature-x', rules=NEXTCLOUD_RULES)

check('latest_on_a_branch_becomes_the_suffix', '''
services:
  app: {build: ., image: mwaeckerlin/nextcloud}
''', 'app', [
    {'source': 'mwaeckerlin/nextcloud:33', 'tags': ['mwaeckerlin/nextcloud:33', 'mwaeckerlin/nextcloud:33-20260926']},
], branch='33', rules=[{'branch': '([0-9]+)', 'suffix': '-\\1'}])

check('same_image_once', '''
services:
  one: {build: ., image: mwaeckerlin/y}
  two: {build: ., image: mwaeckerlin/y}
''', 'one two', [
    {'source': 'mwaeckerlin/y:latest', 'tags': ['mwaeckerlin/y:latest', 'mwaeckerlin/y:20260926']},
])

check('no_image_name_skipped', '''
services:
  test-client: {build: other}
  app: {build: ., image: mwaeckerlin/z}
''', 'app', [
    {'source': 'mwaeckerlin/z:latest', 'tags': ['mwaeckerlin/z:latest', 'mwaeckerlin/z:20260926']},
])

SUBMODULE = '[submodule "sub"]\n\tpath = sub\n\turl = git@github.com:mwaeckerlin/child.git\n'
check('submodule_skipped', '''
services:
  own: {build: ., image: mwaeckerlin/own}
  child: {build: sub, image: mwaeckerlin/child}
''', 'own', [
    {'source': 'mwaeckerlin/own:latest', 'tags': ['mwaeckerlin/own:latest', 'mwaeckerlin/own:20260926']},
], gitmodules=SUBMODULE)

check('nothing_own_fails', '''
services:
  child: {build: sub, image: mwaeckerlin/child}
''', None, None, gitmodules=SUBMODULE)

# The two shell steps run with stand-ins for docker and npm that only record
# their arguments, so the test measures which tags they create and push.
def shell_step(job, name, env):
    step = next(s for s in workflow['jobs'][job]['steps'] if s.get('name') == name)
    with tempfile.TemporaryDirectory() as d:
        log = os.path.join(d, 'calls')
        for tool in ('docker', 'npm'):
            path = os.path.join(d, tool)
            open(path, 'w').write(f'#!/bin/sh\necho "{tool} $*" >> {log}\n')
            os.chmod(path, 0o755)
        subprocess.run(['bash', '-e', '-c', step['run']], check=True, capture_output=True, text=True,
                       env={**os.environ, 'PATH': d + ':' + os.environ['PATH'], **env})
        return open(log).read().splitlines()


def check_calls(name, got, expected):
    global passed, failed
    if got == expected:
        passed += 1
        print(f'  PASS  {name}')
    else:
        failed += 1
        print(f'  FAIL  {name}: expected {expected}, got {got}')


STAGE = json.dumps([['mwaeckerlin/nextcloud:nginx', 'mwaeckerlin/nextcloud:nginx-33'],
                    ['mwaeckerlin/x:latest', 'mwaeckerlin/x:latest']])
check_calls('arch_step_tags_and_runs_deploy', shell_step('build', 'deploy under the architecture tag',
                                                          {'STAGE': STAGE, 'ARCH': 'arm64'}), [
    'docker tag mwaeckerlin/nextcloud:nginx mwaeckerlin/nextcloud:nginx-33-arm64',
    'docker tag mwaeckerlin/x:latest mwaeckerlin/x:latest-arm64',
    'npm run deploy',
])
PUBLISH = json.dumps([{'source': 'mwaeckerlin/x:latest',
                       'tags': ['mwaeckerlin/x:latest', 'mwaeckerlin/x:20260926', 'mwaeckerlin/x:1.3.2']}])
check_calls('deploy_step_joins_into_every_tag', shell_step('deploy', 'join the architectures into all tags',
                                                            {'PUBLISH': PUBLISH, 'ARCHITECTURES': 'amd64 arm64'}), [
    'docker buildx imagetools create -t mwaeckerlin/x:latest -t mwaeckerlin/x:20260926 -t mwaeckerlin/x:1.3.2 '
    'mwaeckerlin/x:latest-amd64 mwaeckerlin/x:latest-arm64',
])

# The weekly run starts the workflow on every version branch a rule names, and
# on no other; git answers with a fixed list of branches.
branch_step = next(s for s in workflow['jobs']['branches']['steps'] if s.get('name', '').startswith('start the weekly'))
with tempfile.TemporaryDirectory() as d:
    log = os.path.join(d, 'calls')
    heads = ''.join(f'0000 refs/heads/{b}\\n' for b in ('master', 'new', 'new-32', 'new-33', 'feature-x', '33'))
    open(os.path.join(d, 'git'), 'w').write(f'#!/bin/sh\nprintf "{heads}"\n')
    open(os.path.join(d, 'gh'), 'w').write(f'#!/bin/sh\necho "gh $*" >> {log}\n')
    for tool in ('git', 'gh'):
        os.chmod(os.path.join(d, tool), 0o755)
    subprocess.run([sys.executable, '-c', branch_step['run']], check=True, capture_output=True, text=True,
                   env={**os.environ, 'PATH': d + ':' + os.environ['PATH'], 'REF_NAME': 'new',
                        'BRANCH_TAGS': json.dumps(NEXTCLOUD_RULES)})
    check_calls('weekly_run_starts_every_version_branch', open(log).read().splitlines(), [
        'gh workflow run docker.yml --ref new-32',
        'gh workflow run docker.yml --ref new-33',
    ])

# A called workflow gets at most the rights of the caller's token, and GitHub
# checks the `permissions` of every job at start, also of a job whose `if` is
# false: a job asking for more ends every run of a read-only repository in
# startup_failure. The rights come from the caller, which grants them only
# where it needs them (a caller with `branch-tags` grants `actions: write`).
check_calls('no_job_asks_for_its_own_rights',
            [job for job, body in workflow['jobs'].items() if 'permissions' in body], [])

print(f'\n==> Workflow contract results: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
EOF
