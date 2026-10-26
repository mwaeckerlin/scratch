#!/usr/bin/env bash
# Check contract: a scheduled run of the reusable workflow builds only when a
# source of an image changed.
#
# The steps that select, decide, label, build, push and join are taken out of
# .github/workflows/docker-image.yml and run against the real registry of
# tests/check/docker-compose.yml and a web server this test serves, so an
# image goes the whole way from the check to the published tag and back:
# - a published image without a record of its sources, or none at all, builds
# - unchanged parents and downloads do not build, and the check stays within
#   one manifest GET per parent and three per published image
# - a changed parent digest, a changed download and a new release build
# - an image older than `rebuild-days` builds
# - a push and a manual start always build, a start by the scheduled run checks
# - the record the check computes reaches the labels of the published image
# - a lookup that fails for another reason than a missing image fails the run
#
# Usage: tests/check-contract.sh

set -uo pipefail

cd "$(dirname "$0")/.."

export REGISTRY_PORT="${REGISTRY_PORT:-45591}" WEB_PORT="${WEB_PORT:-45592}"
STACK=(docker compose -f tests/check/docker-compose.yml -p scratch-check)
trap '"${STACK[@]}" down --volumes --remove-orphans > /dev/null 2>&1' EXIT
"${STACK[@]}" up --detach --wait || exit 1

python3 - <<'EOF'
import datetime, itertools, json, os, re, shutil, subprocess, sys, tempfile, threading, time, urllib.request, yaml
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

workflow = yaml.safe_load(open('.github/workflows/docker-image.yml'))
jobs = workflow['jobs']


def step(job, key, value):
    return next(s for s in jobs[job]['steps'] if s.get(key) == value)


SELECT = step('check', 'id', 'select')['run']
DECIDE = step('check', 'id', 'decide')['run']
JOIN = step('deploy', 'name', 'join the architectures into all tags')['run']
# the steps of the build job that make and publish the images, in the order the job runs them
LABEL = 'label the images with the sources they are built from'
PROVE = 'prove that the pushed images carry the labels of their sources'
ORDER = [s['name'] for s in jobs['build']['steps'] if s.get('name') in
         ('build', 'test', LABEL, 'deploy under the architecture tag', PROVE)]
REGISTRY = f"localhost:{os.environ['REGISTRY_PORT']}"
WEB = f"http://127.0.0.1:{os.environ['WEB_PORT']}"
STACK = ['docker', 'compose', '-f', 'tests/check/docker-compose.yml', '-p', 'scratch-check']
PARENTS, DOWNLOADS = 'org.mwaeckerlin.parents', 'org.mwaeckerlin.downloads'

passed = failed = 0


def check(name, ok, detail=''):
    global passed, failed
    if ok:
        passed += 1
        print(f'  PASS  {name}')
    else:
        failed += 1
        print(f'  FAIL  {name}: {detail}')


def wait_until_ready(url):
    deadline = time.monotonic() + 60
    while True:
        try:
            urllib.request.urlopen(url, timeout=5)
            return
        except Exception as error:
            if time.monotonic() > deadline:
                sys.exit(f'{url} never answered: {error}')
            time.sleep(0.5)


def execute(command, **kwargs):
    run = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if run.returncode:
        sys.exit(f'{" ".join(command[:4])} failed:\n{run.stdout}{run.stderr}')
    return run.stdout


def docker(*args):
    return execute(['docker', *args])


local_images = set()


def push_image(name, content):
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, 'content'), 'w').write(content)
        open(os.path.join(d, 'Dockerfile'), 'w').write('FROM scratch\nCOPY content /content\n')
        docker('build', '--quiet', '-t', name, d)
    local_images.add(name)
    docker('push', '--quiet', name)


def manifest_requests():
    """Manifest requests the registry logged, read until the log stops growing."""
    previous = None
    deadline = time.monotonic() + 30
    while True:
        found = re.findall(r'"(GET|HEAD) /v2/\S+/manifests/', execute([*STACK, 'logs', '--no-log-prefix', 'registry']))
        counts = (found.count('GET'), found.count('HEAD'))
        if counts == previous or time.monotonic() > deadline:
            return counts
        previous = counts
        time.sleep(0.5)


def outputs(path):
    return dict(line.split('=', 1) for line in open(path).read().splitlines())


def write(directory, files):
    for name, content in files.items():
        os.makedirs(os.path.dirname(os.path.join(directory, name)), exist_ok=True)
        open(os.path.join(directory, name), 'w').write(content)


# `/file` answers with an ETag; `/o/r/releases/latest/download/tool` redirects
# to the current release the way GitHub does, and the release asset answers
# with another ETag on every request, as GitHub's signed asset addresses do.
# `/skills.git` is a git repository, served the way git's dumb HTTP protocol
# reads it; its page answers with another ETag on every request, as github.com
# does for `https://github.com/<owner>/<repository>.git`.
versions = {'file': 1, 'release': 1}
asset = itertools.count()
repository = tempfile.mkdtemp()


def git(*args):
    return execute(['git', '-C', repository, '-c', 'user.name=test', '-c', 'user.email=test@localhost', *args]).strip()


def commit(content):
    """A new commit on master, published for the dumb HTTP protocol; returns its id."""
    write(repository, {'skills/skill.md': content})
    git('add', '.')
    git('commit', '--quiet', '-m', content)
    git('update-server-info')
    return git('rev-parse', 'HEAD')


git('init', '--quiet', '--initial-branch=master')
first_commit = commit('one')


class Downloads(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?', 1)[0]
        if path.startswith('/skills.git/'):
            served = os.path.join(repository, '.git', path[len('/skills.git/'):])
            if os.path.isfile(served):
                content = open(served, 'rb').read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return
        self.do_HEAD()

    def do_HEAD(self):
        if self.path == '/skills.git':
            self.send_response(200)
            self.send_header('ETag', f'W/"page-{next(asset)}"')
        elif self.path == '/file':
            self.send_response(200)
            self.send_header('ETag', f'"file-{versions["file"]}"')
        elif self.path == '/o/r/releases/latest/download/tool':
            self.send_response(302)
            self.send_header('Location', f'/o/r/releases/download/v{versions["release"]}/tool')
        elif self.path.startswith('/o/r/releases/download/'):
            self.send_response(200)
            self.send_header('ETag', f'"asset-{next(asset)}"')
        else:
            self.send_response(404)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(('127.0.0.1', int(os.environ['WEB_PORT'])), Downloads)
threading.Thread(target=server.serve_forever, daemon=True).start()

wait_until_ready(f'http://{REGISTRY}/v2/')

COMPOSE = f'''
services:
  app: {{build: ., image: "{REGISTRY}/x/app"}}
  tool: {{build: {{context: ., dockerfile: Dockerfile.tool}}, image: "{REGISTRY}/x/app:tool"}}
  database: {{image: postgres}}
'''

with tempfile.TemporaryDirectory() as project, tempfile.TemporaryDirectory() as reading, \
        tempfile.TemporaryDirectory() as temp:
    # the project that is built and published; the stage `fetch` is not
    # needed by the image, so the build never fetches its downloads
    write(project, {'docker-compose.yml': COMPOSE, 'Dockerfile': f'''ARG BASE={REGISTRY}/x/parent
FROM ${{BASE}} AS build
FROM build AS fetch
ADD {WEB}/file /file
ADD {WEB}/skills.git#master:skills /skills/
RUN wget -O /usr/bin/tool {WEB}/o/r/releases/latest/download/tool
FROM scratch
COPY --from=build /content /content
''', 'Dockerfile.tool': f'FROM {REGISTRY}/x/parent:latest\n',
                     # the test builds the published images once more through a compose file of its
                     # own, as the end to end tests of mwaeckerlin/nginx do with `context: ../..`
                     'tests/docker-compose.yml': f'''
services:
  app: {{build: {{context: ..}}, image: "{REGISTRY}/x/app"}}
  tool: {{build: {{context: .., dockerfile: Dockerfile.tool}}, image: "{REGISTRY}/x/app:tool"}}
''',
                     'package.json': json.dumps({'name': 'x', 'scripts': {
                         'build': 'docker compose build',
                         'test': 'npm run build && docker compose -f tests/docker-compose.yml build',
                         'deploy': 'docker compose push app tool'}})})
    # the project whose Dockerfiles are only read
    write(reading, {'docker-compose.yml': COMPOSE, 'Dockerfile': f'''# a stage, scratch and an image of this repository are no parents
ARG BASE={REGISTRY}/x/parent
FROM ${{BASE}} AS build
FROM scratch
COPY --from=build /content /content
COPY --from={REGISTRY}/x/app:tool /content /tool
ADD {WEB}/file /file
RUN wget -O /usr/bin/tool {WEB}/o/r/releases/latest/download/tool \\
 && wget -O /archive {WEB}/$VERSION/archive
''', 'Dockerfile.tool': f'FROM {REGISTRY}/x/parent:latest\n'})

    def select():
        selected = os.path.join(temp, 'select-output')
        open(selected, 'w').close()
        execute([sys.executable, '-c', SELECT], cwd=project,
                env={**os.environ, 'GITHUB_OUTPUT': selected, 'ARCH': 'amd64', 'RUNNER_TEMP': temp,
                     'REF_NAME': 'master', 'RELEASE': '', 'BRANCH_TAGS': '[]', 'BUILD_DATE': '20261022'})
        return outputs(selected)

    selection = select()

    def decide(event='schedule', actor='github-actions[bot]', days='7', now=None, cwd=project, force=''):
        output = os.path.join(temp, 'decide-output')
        open(output, 'w').close()
        run = subprocess.run([sys.executable, '-c', DECIDE], cwd=cwd, capture_output=True, text=True,
                             env={**os.environ, 'GITHUB_OUTPUT': output, 'SERVICES': selection['services'],
                                  'PUBLISH': selection['publish'], 'EVENT': event, 'ACTOR': actor, 'FORCE': force,
                                  'REBUILD_DAYS': days, 'NOW': now.isoformat() if now else ''})
        if run.returncode:
            return None, None, run.stdout + run.stderr
        result = outputs(output)
        return result['build'] == 'true', json.loads(result['record']), run.stdout

    def run_step(job, name, context, may_fail=False):
        """Runs a step of the workflow with its own env, its expressions filled from `context`, in a fresh
        checkout of the project; returns what it writes to GITHUB_OUTPUT, or with `may_fail` the finished run."""
        found = step(job, 'name', name)

        def resolve(text):
            return re.sub(r'\$\{\{\s*(.*?)\s*\}\}', lambda m: context.get(m.group(1), ''), str(text))

        output = os.path.join(temp, 'step-output')
        open(output, 'w').close()
        env = {**os.environ, 'RUNNER_TEMP': temp, 'GITHUB_OUTPUT': output,
               **{k: resolve(v) for k, v in (found.get('env') or {}).items()}}
        command = [sys.executable, '-c'] if found.get('shell', '').startswith('python3') else ['bash', '-e', '-c']
        if may_fail:
            return subprocess.run([*command, resolve(found['run'])], cwd=project, env=env, capture_output=True, text=True)
        execute([*command, resolve(found['run'])], cwd=project, env=env)
        return outputs(output)

    def publish(record=None, skip=()):
        """Builds, tests, labels, pushes and joins the images through the steps of a run, in the order of the build
        job, labelled with the record, or with none, as an image published before the check; the test command of the
        project builds the images once more, through the compose file of its tests."""
        chosen = select()
        context = {'matrix.arch': 'amd64', 'inputs.test': 'npm test', **{f'steps.select.outputs.{k}': v for k, v in chosen.items()}}
        context['needs.check.outputs.record'] = json.dumps(record or {})
        for image, staging in json.loads(chosen['stage']):
            local_images.update((image, f'{staging}-amd64'))
        for name in ORDER:
            if name in skip:
                continue
            if name == PROVE and skip:
                return run_step('build', name, context, may_fail=True)
            run_step('build', name, context)
        execute(['bash', '-e', '-c', JOIN], env={**os.environ, 'PUBLISH': chosen['publish'], 'ARCHITECTURES': 'amd64'})

    def published_labels(tag):
        image = json.loads(docker('buildx', 'imagetools', 'inspect', f'{REGISTRY}/x/app:{tag}', '--format', '{{json .Image}}'))
        if 'created' not in image:
            image = image.get('linux/amd64') or next(iter(image.values()))
        return (image.get('config') or {}).get('Labels') or {}

    try:
        check('the_check_runs_before_the_build',
              jobs['build']['needs'] == 'check' and 'needs.check.outputs.build' in jobs['build']['if'],
              f"build needs {jobs['build'].get('needs')}, if {jobs['build'].get('if')}")
        check('check_and_build_select_the_same_images', step('check', 'id', 'select') == step('build', 'id', 'select'))
        check('build_job_runs_the_steps_the_round_trip_runs', len(ORDER) == 5, ORDER)

        push_image(f'{REGISTRY}/x/parent', 'one')
        build, record, out = decide(event='push', actor='marc', cwd=reading)
        parents = json.loads(record[PARENTS]) if record else {}
        downloads = json.loads(record[DOWNLOADS]) if record else {}
        check('record_names_parents_and_downloads',
              list(parents) == [f'{REGISTRY}/x/parent:latest'] and parents[f'{REGISTRY}/x/parent:latest'].startswith('sha256:')
              and downloads == {f'{WEB}/file': '"file-1"',
                                f'{WEB}/o/r/releases/latest/download/tool': f'release {WEB}/o/r/releases/download/v1/tool'}
              and '$VERSION/archive is assembled in shell code' in out,
              f'{record}\n{out}')

        build, record, out = decide()
        check('scheduled_run_without_published_image_builds', build is True and 'is not published yet' in out, out)
        check('git_download_is_its_commit',
              json.loads(record[DOWNLOADS]).get(f'{WEB}/skills.git#master:skills') == f'commit {first_commit}', record)

        publish()
        build, _, out = decide()
        check('image_without_record_builds', build is True and 'carries no record of its sources' in out, out)
        named = re.search(f'{re.escape(REGISTRY)}/x/app:latest carries the labels: (.*)', out)
        check('check_names_missing_labels', named is not None and PARENTS not in named.group(1), out)

        publish(record)
        check('record_round_trip_through_the_labels',
              all({k: published_labels(t).get(k) for k in record} == record for t in ('latest', 'tool')),
              published_labels('latest'))
        built = published_labels('latest').get('org.mwaeckerlin.built', '')
        check('build_time_is_a_label',
              re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', built) is not None
              and abs((datetime.datetime.now(datetime.timezone.utc)
                       - datetime.datetime.fromisoformat(built.replace('Z', '+00:00'))).total_seconds()) < 600,
              built)
        unlabelled = publish(record, skip=(LABEL,))
        check('push_without_labels_fails_the_run',
              unlabelled.returncode != 0 and 'was pushed without the labels' in unlabelled.stdout,
              unlabelled.stdout + unlabelled.stderr)
        publish(record)
        before = manifest_requests()
        build, again, out = decide()
        after = manifest_requests()
        check('unchanged_sources_do_not_build', build is False and again == record, out)
        named = re.search(f'{re.escape(REGISTRY)}/x/app:latest carries the labels: (.*)', out)
        check('check_names_the_labels_it_reads',
              named is not None and PARENTS in named.group(1) and DOWNLOADS in named.group(1), out)
        gets, heads = after[0] - before[0], after[1] - before[1]
        check('lookups_stay_within_the_pull_budget', gets <= 1 + 3 * 2,
              f'{gets} GET and {heads} HEAD manifest requests for one parent and two published images')
        print(f'        measured: {gets} GET and {heads} HEAD manifest requests for one parent and two published images')

        build, _, out = decide(event='push', actor='marc')
        check('push_always_builds', build is True and 'a push run always builds' in out, out)
        build, _, out = decide(event='workflow_dispatch', actor='marc')
        check('manual_start_always_builds', build is True, out)
        build, _, out = decide(event='workflow_dispatch')
        check('start_by_the_scheduled_run_checks', build is False, out)
        build, _, out = decide(event='workflow_dispatch', force='true')
        check('start_after_a_push_of_the_base_branch_builds', build is True and 'build=true always builds' in out, out)

        versions['file'] += 1
        build, record, out = decide()
        check('changed_download_builds', build is True and f'{WEB}/file changed' in out, out)
        publish(record)

        versions['release'] += 1
        build, record, out = decide()
        check('new_release_builds', build is True and '/o/r/releases/download/v2/tool' in out, out)
        publish(record)

        second_commit = commit('two')
        build, record, out = decide()
        check('new_commit_builds', build is True and 'skills.git#master:skills changed' in out and second_commit in out, out)
        publish(record)

        push_image(f'{REGISTRY}/x/parent', 'two')
        build, record, out = decide()
        check('changed_parent_builds', build is True and f'{REGISTRY}/x/parent:latest changed' in out, out)
        publish(record)
        build, _, out = decide()
        check('built_image_does_not_build_again', build is False, out)

        later = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=8)
        build, _, out = decide(now=later)
        check('image_older_than_rebuild_days_builds', build is True and 'was built 8 days ago' in out, out)
        build, _, out = decide(now=later, days='9')
        check('rebuild_days_sets_the_age', build is False, out)

        with tempfile.TemporaryDirectory() as broken:
            write(broken, {'docker-compose.yml': f'services:\n  app: {{build: ., image: "{REGISTRY}/x/app"}}\n'
                                                 f'  tool: {{build: ., image: "{REGISTRY}/x/app:tool"}}\n',
                           'Dockerfile': 'FROM localhost:1/x/parent\n'})
            build, _, out = decide(cwd=broken)
            check('failed_lookup_fails_the_check', build is None and 'cannot be looked up' in out, out)
    finally:
        for image in local_images:
            subprocess.run(['docker', 'image', 'rm', '--force', image], capture_output=True)
        shutil.rmtree(repository, ignore_errors=True)

print(f'\n==> Check contract results: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
EOF
