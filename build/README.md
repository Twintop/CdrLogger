# Build tooling

| Task | Command |
| --- | --- |
| Build a release zip locally (into `dist\`) | `.\build\stage.ps1` |
| Same, stamping a version | `.\build\stage.ps1 -Version 12.0.1.1 -ReleaseType beta01` |

## Releasing

Before tagging, stamp `## Version:` and `## X-ReleaseDate:` in `CdrLogger.toc`; the packager rewrites neither. Then
push a tag whose version matches the TOC: `12.0.1.1-release`, `12.0.1.1-beta01`, or `12.0.1.1-alpha01`.

The workflow in `.github\workflows\release.yml` runs the checks in `checks.yml` (Lua syntax, and every TOC entry
exists), stages the zip with `stage.ps1` as a workflow artifact, and hands the checkout to the BigWigs packager. The
packager builds the zip, creates the GitHub release with it attached, and uploads to CurseForge and Wago when the
`CF_API_KEY` and `WAGO_API_TOKEN` secrets exist. A tag containing `alpha` or `beta` is a pre-release everywhere. The
changelog is generated from the git commits since the previous tag.

**Dry run.** Run the workflow by hand (workflow_dispatch): the packager builds the zip with `-d` (no uploads, no
GitHub release) and the zip is attached to the run as the `packager` artifact.
