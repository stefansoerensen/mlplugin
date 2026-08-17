# Widget build wiring (Pulse + Assistant)

Both platform widgets are consumed the same way. **They are not installed from
an npm registry.** Each widget's `package.json` carries a `publishConfig`
pointing at a registry, but no consuming app uses it — every app builds the
widget from source inside its own frontend Docker build.

Understand this before editing a frontend `Dockerfile`, `Jenkinsfile`, or
`package.json` in an app repo, or you will "fix" a dependency that isn't broken.

## The mechanism, end to end

**1. `frontend/package.json` — a `file:` dependency on an absolute in-image path**

```json
{
  "dependencies": {
    "@pulse/widget": "file:/pulse/widget",
    "@medialine/assistant": "file:/medialine-assistant/widget"
  }
}
```

Those paths do not exist on your laptop. They exist only inside the Docker
build image, created in step 2. This is why `npm install` on the host fails and
why the [`cloud-only`](../../../rules/cloud-only.md) rule matters here.

**2. `frontend/Dockerfile` — build each widget in its own stage, then copy it in**

```dockerfile
# Build pulse widget from source
FROM node:20-alpine AS widget-builder
WORKDIR /widget
COPY --from=pulse-widget . .
RUN npm install && npm run build

# Build the @medialine/assistant widget from source
FROM node:20-alpine AS assistant-widget-builder
WORKDIR /widget
COPY --from=assistant-widget . .
RUN npm install && npm run build

# Build stage
FROM node:20-alpine AS build
WORKDIR /app

# Copy built pulse widget to the path package.json points at
COPY --from=widget-builder /widget/package.json /pulse/widget/package.json
COPY --from=widget-builder /widget/dist         /pulse/widget/dist
COPY --from=widget-builder /widget/node_modules /pulse/widget/node_modules

# Copy built @medialine/assistant widget
COPY --from=assistant-widget-builder /widget/package.json /medialine-assistant/widget/package.json
COPY --from=assistant-widget-builder /widget/dist         /medialine-assistant/widget/dist
COPY --from=assistant-widget-builder /widget/node_modules /medialine-assistant/widget/node_modules

COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY . .

ARG VITE_API_URL
ARG VITE_ASSISTANT_API_URL
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_ASSISTANT_API_URL=$VITE_ASSISTANT_API_URL

RUN npx vite build
```

`COPY --from=pulse-widget` refers to a **named build context**, not a stage —
supplied by Jenkins in step 3.

**3. `Jenkinsfile` — clone the widget repos and pass them as build contexts**

```groovy
stage('Frontend') {
    steps {
        withCredentials([usernamePassword(credentialsId: 'gitea-credentials', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
            sh """
                git clone http://\${GIT_USER}:\${GIT_PASS}@gitea:3000/medialine/pulse.git _pulse_tmp
                git clone http://\${GIT_USER}:\${GIT_PASS}@gitea:3000/medialine/assistant-service.git _assistant_tmp
                docker build -t ${IMAGE_FRONTEND}:${env.BUILD_VERSION} \
                    -t ${IMAGE_FRONTEND}:latest \
                    --build-context pulse-widget=_pulse_tmp/widget \
                    --build-context assistant-widget=_assistant_tmp/widget \
                    --build-arg VITE_ASSISTANT_API_URL=https://assistant.tasktool.medialine.com \
                    ./frontend
                rm -rf _pulse_tmp _assistant_tmp
            """
        }
    }
}
```

Both widgets always build from `main` of their repo. There is no version
pinning — a breaking widget change breaks every consumer's next build, which is
deliberate: it surfaces immediately rather than rotting in a lockfile.

## Consequences worth knowing

- **`--build-context` requires BuildKit.** Docker 23+ / buildx. Already true on
  the Jenkins agents.
- **Adding only one widget?** Include only that widget's stage, context, and
  clone. The two are fully independent.
- **`npm install` on your host will fail** on the `file:` dependency. That is
  expected and is not a bug to fix — see [`cloud-only`](../../../rules/cloud-only.md).
  For editor type-checking, `tsc --noEmit` still works because the widget ships
  its own `.d.ts` once built; if your editor complains about the missing module,
  ignore it rather than rewriting the dependency.
- **Don't switch to a registry install** without changing all consumers plus
  both Jenkinsfiles. The `file:`-plus-build-context approach is the current
  standard.
