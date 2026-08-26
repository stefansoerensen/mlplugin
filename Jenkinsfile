/**
 * claude-plugin-platform CI
 *
 * Validates the plugin marketplace + plugin manifest on every branch
 * and PR build. No deploy step — distribution is git-pull-based:
 * developer machines `claude plugin marketplace update medialine`
 * fetches the latest commit; downstream repos pin via .claude/plugins.json.
 *
 * On main, additionally tags the commit with the plugin's version from
 * medialine-platform/.claude-plugin/plugin.json so semver pins resolve.
 */

pipeline {
    agent any

    options {
        timeout(time: 10, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_BRANCH_NAME = (env.GIT_BRANCH ?: 'main').replaceAll('^origin/', '')
                    env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                }
                echo "Branch: ${env.GIT_BRANCH_NAME} @ ${env.GIT_COMMIT_SHORT}"
            }
        }

        stage('Validate manifests') {
            steps {
                sh '''
                    set -e
                    # marketplace.json must be valid JSON with required fields
                    python3 -c "
import json, sys
m = json.load(open('.claude-plugin/marketplace.json'))
assert m.get('name'), 'marketplace.json missing name'
assert m.get('owner'), 'marketplace.json missing owner'
assert isinstance(m.get('plugins'), list) and m['plugins'], 'marketplace.json missing plugins'
for p in m['plugins']:
    assert p.get('name'), 'plugin entry missing name'
    assert p.get('source'), 'plugin entry missing source'
print('marketplace.json OK: %d plugin(s)' % len(m['plugins']))
"
                    # plugin.json must be valid JSON with required fields
                    python3 -c "
import json
p = json.load(open('medialine-platform/.claude-plugin/plugin.json'))
assert p.get('name'), 'plugin.json missing name'
assert p.get('description'), 'plugin.json missing description'
print('plugin.json OK: %s @ %s' % (p['name'], p.get('version','unversioned')))
"
                '''
            }
        }

        stage('Validate skills') {
            steps {
                sh '''
                    set -e
                    # Each skill must be a directory with SKILL.md and a description frontmatter
                    for skill in medialine-platform/skills/*/; do
                        [ -f "$skill/SKILL.md" ] || { echo "MISSING SKILL.md in $skill"; exit 1; }
                        head -10 "$skill/SKILL.md" | grep -q "^description:" || {
                            echo "SKILL.md in $skill has no description frontmatter"; exit 1;
                        }
                    done
                    echo "$(ls -d medialine-platform/skills/*/ | wc -l) skill(s) validated"
                '''
            }
        }

        stage('Validate hooks.json') {
            steps {
                sh '''
                    python3 -c "
import json
h = json.load(open('medialine-platform/hooks/hooks.json'))
assert h.get('hooks'), 'hooks.json missing hooks key'
print('hooks.json OK: %s event(s)' % len(h['hooks']))
"
                '''
            }
        }

        stage('Version bump check') {
            when { not { branch 'main' } }
            steps {
                sh '''
                    set -e
                    git fetch origin main --quiet 2>/dev/null || git fetch origin main

                    # Only medialine-platform/** is installed. plugin.json itself is
                    # excluded: a lone version change is not a payload change.
                    CHANGED=$(git diff --name-only origin/main...HEAD -- medialine-platform/ \
                              | grep -v "^medialine-platform/.claude-plugin/plugin.json$" || true)

                    if [ -z "$CHANGED" ]; then
                        echo "No payload change under medialine-platform/ — version bump not required"
                        exit 0
                    fi

                    echo "Payload changed:"
                    echo "$CHANGED" | sed "s/^/  /"

                    OLD=$(git show origin/main:medialine-platform/.claude-plugin/plugin.json \
                          | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
                    NEW=$(python3 -c "import json; print(json.load(open('medialine-platform/.claude-plugin/plugin.json'))['version'])")

                    if [ "$OLD" = "$NEW" ]; then
                        echo ""
                        echo "FAIL: payload changed but version is still $OLD."
                        echo "Installs are keyed on the version string, so an unbumped change"
                        echo "reaches NO installation — it sits in the marketplace clone looking"
                        echo "merged while every session keeps loading the old copy."
                        echo "Bump medialine-platform/.claude-plugin/plugin.json (see README > Versioning)."
                        exit 1
                    fi

                    echo "Version bump OK: $OLD -> $NEW"
                '''
            }
        }

        stage('Tag version (main only)') {
            when { branch 'main' }
            steps {
                sh '''
                    VERSION=$(python3 -c "import json; print(json.load(open('medialine-platform/.claude-plugin/plugin.json')).get('version','0.0.0'))")
                    echo "Plugin version: v${VERSION}"
                    # Tag the commit if not already tagged
                    if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
                        echo "v${VERSION} already tagged — skip"
                    else
                        echo "Would tag v${VERSION} (commit ${GIT_COMMIT_SHORT})"
                        # Actual tag-push deferred until we wire the gitea-credentials in this job
                    fi
                '''
            }
        }
    }

    post {
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline FAILED" }
    }
}
