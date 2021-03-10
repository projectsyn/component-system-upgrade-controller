# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Index and reference documentation
- Add support to define tolerations in SUC pods
- Allow to override the SUC pod affinity
- Rename parameter backoff_limit to job_backoff_limit
- Change parameters.cluster.dist to parameters.facts.distribution ([#7])
- Add ArgoCD wave number to plan CRD object
- Update the SUC image from v0.5 to docker.io/rancher/system-upgrade-controller:v0.6.2
- Support for arbitrary argument pass-through for plans ([#16])

### Fixed
- Allow ArgoCD to skip dry run for plan resources if CRD is missing ([#14])
- Fix plan creation when explicit channel is provided ([#15])

[Unreleased]: https://github.com/projectsyn/component-system-upgrade-controller/compare/2606b0b...HEAD

[#7]: https://github.com/projectsyn/component-system-upgrade-controller/pull/7
[#14]: https://github.com/projectsyn/component-system-upgrade-controller/pull/14
[#15]: https://github.com/projectsyn/component-system-upgrade-controller/pull/15
[#16]: https://github.com/projectsyn/component-system-upgrade-controller/pull/16
