# Student Portal: end-to-end DevSecOps pipeline lab

You write the **workflows** (`.github/workflows/*.yml`). Everything else is supplied: a small app with tests,
a hardened Dockerfile, Terraform for cheap resources, a Helm chart, Argo CD Applications, OIDC bootstrap,
and deliberately broken files to prove each check works.

**No second cluster.** dev, staging and prod are three Argo CD Applications on your *existing* cluster, each
with its own namespace (`portal-dev`, `portal-staging`, `portal-prod`), its own Git branch and its own values file.
Terraform creates only free or near-free AWS resources (an S3 bucket, an SSM parameter, one ECR repo).

## 0. FOCUSED PATH (the one Jasleen chose): 3 workflows, about 5 to 6 hours

- Setup, minimal: state bucket + `bootstrap/`; only GitHub environments `dev` and `production`; only branches `argo-dev` and `argo-prod`;
  only the dev and prod Argo CD Applications. Use roles `plan`, `apply-dev`, `apply-prod`, `ecr-push`; ignore the rest.
- `pr.yml`: ONE file, checks written inline (no reusable workflows): terraform fmt + validate, Checkov, pip-audit, Hadolint,
  Gitleaks, tests; `infra-plan` with the read-only role; `quality-gate` (`needs` + `if: always()`), the only required check.
  Proofs: remove `always()`; one planted flaw.
- `infra-apply.yml`: dev, then prod behind the approval gate.
- `app-build.yml`: build once, SHA tag, Trivy scan, push to ECR, bot commit to `argo-dev`, then the smoke job (section 4E),
  plus a manual prod promote job (prod environment approval, bot commit to `argo-prod`).
- Skipped for now: staging, reusable-workflow split, SAST job, plan-JSON scan, nightly drift/deep scans, Cosign/SBOM, most of the break-it table.
  Keep only three break-its: missing `id-token: write`; dropped `pull_request` subject; shared state key.

## 1. What is in the repo

```
app/                 Flask API + tests (unit, integration, smoke)        <- scanned + tested + built
Dockerfile           hardened two-stage image (numeric non-root UID)
infra/               Terraform: modules/app_bucket, ECR (dev only), per-env tfvars + backend files
bootstrap/           ONE-TIME Terraform: GitHub OIDC provider + 6 IAM roles (you apply it by hand)
k8s/chart/           Helm chart (hardened securityContext, probes)
k8s/environments/    dev.yaml / staging.yaml / prod.yaml  (image.tag is the line your bot rewrites)
k8s/argocd/          the three Argo CD Applications
planted/             files with deliberate flaws, used for "break it on purpose" proofs
.checkov.yaml        Checkov config, every skip has a reason
infra/.tflint.hcl    TFLint config
```

## 2. One-time setup (about 30 minutes)

1. Create a **new GitHub repo**, push this folder to `main`. Create branches `argo-dev`, `argo-staging`, `argo-prod`
   from `main` (they only ever receive the bot's one-line image-tag commits).
2. Pick or create an S3 bucket for Terraform state. Put its name in `infra/envs/*.backend.hcl` (replace the placeholder).
3. Apply `bootstrap/` from your laptop. It prints six role ARNs. Store them as GitHub **environment** or repo
   **variables** (these are identifiers, not secrets).
   - If your repo uses GitHub's immutable OIDC subject format, first decode a real token's `sub` claim and pass
     `-var subject_prefix=...` (see the variable's comment). This is the Part 13 Topic 4 debugging skill.
4. GitHub **environments**: `dev`, `staging`, `production`. Add a required reviewer on `production`.
   (The apply roles trust `environment:dev`, `environment:staging`, `environment:production`: names must match exactly.)
5. Replace `REPLACE_OWNER/REPLACE_REPO` in `k8s/argocd/applications.yaml`, then
   `kubectl apply -n argocd -f k8s/argocd/applications.yaml` against your existing cluster.
6. Replace `REPLACE_ME.dkr.ecr...` in `k8s/environments/*.yaml` with your ECR URL after the first dev apply creates it.
7. Terraform run order for a first deploy: `bootstrap` (laptop) -> infra dev apply (creates the ECR repo) -> image build/push.

Run the app tests locally any time: `cd app && pip install -r requirements-dev.txt && pytest -q`
(smoke tests skip until you set `BASE_URL`).

## 3. Role map (what each workflow job assumes)

| Role | Trusted subject | Used by | Can do |
|---|---|---|---|
| `gha-plan` | `pull_request` | PR plan job | read AWS, read state, write only the `.tflock` file |
| `gha-apply-dev` | `environment:dev` | apply dev | create/change dev resources |
| `gha-apply-stage` | `environment:staging` | apply staging | same, staging state |
| `gha-apply-prod` | `environment:production` | apply prod | same, prod state, after approval |
| `gha-ecr-push` | `ref:refs/heads/main` | build job | push images to the one repo |
| `gha-nightly-read` | `ref:refs/heads/main` | nightly drift | read-only |

## 4. The workflows YOU write

Write them in this order. Each one lists inputs, jobs and the "proof" that shows it works. No YAML is given.

### A. `reusable-iac-checks.yml` (trigger: `workflow_call`)
Runs in `infra/`: `terraform fmt -check`, `init -backend=false` + `validate`, TFLint, Checkov (`.checkov.yaml`).
**Proof:** call it from a scratch workflow; copy `planted/insecure.tf` into `infra/` and watch Checkov fail.

### B. `reusable-app-checks.yml` (trigger: `workflow_call`)
Runs tests with coverage, `pip-audit` on `requirements.txt`, Hadolint on the Dockerfile, Gitleaks.
**Proof:** swap in `planted/requirements-vulnerable.txt`, `planted/Dockerfile.bad`, `planted/fake_secret.env`, one at a time.

### C. `pr.yml` (trigger: `pull_request` on `main`, **no `paths:` filter**)
Jobs: `changes` (decide whether infra/app changed), call A and B conditionally, `infra-plan`
(assume `gha-plan`, needs `id-token: write`, then scan the plan JSON with Checkov), a **non-blocking** SAST job
(CodeQL, `continue-on-error`), and one `quality-gate` job with `needs: [...]` and `if: always()` that fails if any needed job
failed or was cancelled. Only `quality-gate` is a required check in the ruleset.
**Proofs:**
1. Remove `if: always()` -> a failed scan lets the gate be *skipped* and the PR merges green. Put it back.
2. Make `pr.yml` path-filtered -> docs-only PR waits forever on a required check. Remove the filter.
3. Copy `planted/app_vulnerable.py` -> SAST reports it, but does not block (non-blocking tier).

### D. `infra-apply.yml` (trigger: push to `main` touching `infra/**`, plus `workflow_dispatch`)
Sequential jobs dev -> staging -> prod, each with `environment:` set, each assuming its own role, each using its own
`envs/<env>.tfvars` and `envs/<env>.backend.hcl`. Plan, then apply the saved plan. Prod pauses for the reviewer.
**Proof:** the `terraform output` of each environment shows a different bucket name; the state bucket has three separate keys.

### E. `app-build.yml` (trigger: push to `main` touching app files)
Build **once**, tag with `github.sha`, Trivy-scan the local image (fail on HIGH/CRITICAL with a fix), push to ECR
(`gha-ecr-push`), then a bot commit on `argo-dev` that changes only `image.tag` in `k8s/environments/dev.yaml`.
Optional extension: Cosign sign by digest + SBOM.
**Smoke job (Topic 7):** after the bot commit, wait for Argo CD to sync `portal-dev`, then run the smoke tests against the
live service: `BASE_URL=<dev service URL> EXPECTED_SHA=${{ github.sha }} pytest -m smoke` (from `app/`). The URL can be an
in-cluster service reached by `kubectl port-forward`, or an ingress if you have one. The job fails if `/health` is not 200 or
`/version` does not report the SHA you just built, which proves the new image is the one actually running.
Stretch: on failure, revert the bot commit on `argo-dev` (automatic rollback, the "what changes in production" idea).
**Proof:** Argo CD syncs `portal-dev`; `curl <svc>/version` returns the commit SHA; break the image on purpose and watch the smoke job fail.

### F. `promote.yml` (trigger: `workflow_dispatch` with input `sha`)
Staging job (updates `argo-staging`), then production job (`environment: production`, approval, updates `argo-prod`).
Never rebuilds. It verifies the SHA already exists in ECR before touching a branch.
**Proof:** all three `/version` endpoints show the same SHA. With `IMMUTABLE` tags, try pushing the same tag twice: it must be rejected.

### G. `nightly.yml` (trigger: `schedule`)
Drift: `terraform plan -detailed-exitcode` per env (exit code 2 = drift, open an issue or fail the run);
deep scans (Trivy image + fs, Checkov full). Uses `gha-nightly-read`.
**Proof:** change a bucket tag in the console, run it manually, see exit code 2.

## 5. Break-it-on-purpose checklist (the interview stories)

| Break | You should see | The concept |
|---|---|---|
| Both envs point at the same `key` in a backend file | second apply wants to destroy the first env's resources | the Oct 3 shared-state incident |
| Drop `pull_request` from `gha-plan`'s trust | `Not authorized to perform sts:AssumeRoleWithWebIdentity` | OIDC `sub` matching |
| Remove `id-token: write` | "Unable to get ACTIONS_ID_TOKEN_REQUEST_URL" style failure | workflow permissions |
| Set prod `replicaCount` to 5 in `prod.yaml` only | only `portal-prod` changes | env isolation by values file |
| `kubectl delete deploy student-portal -n portal-dev` | Argo CD heals it (selfHeal) | GitOps |
| Edit the deployment by hand in `portal-dev` | Argo CD reverts it | drift vs desired state |

## 6. Honest caveats

- I could not run `terraform`, `tflint`, `checkov`, `actionlint` or `helm` in my sandbox. The app tests were run and pass
  (13 passed, 2 skipped). The Terraform, chart and manifests are written carefully but **unvalidated**: expect to fix a
  typo or two, and run `terraform validate` / `helm template k8s/chart -f k8s/environments/dev.yaml` first.
- The provider pin (`~> 5.0`), TFLint plugin version (`0.38.0`) and Checkov check IDs in `.checkov.yaml` are from memory:
  if a skip ID is not recognised or the plugin fails to download, look up the current value.
- Apply-role permissions are service-wide wildcards for lab speed. Narrowing them to resource ARNs is a good follow-up.
- Pin every third-party action by commit SHA when you write the workflows, and look up current action versions yourself in the marketplace.
- Costs: S3, SSM and ECR here are cents per month. Your existing cluster is the only real cost.
