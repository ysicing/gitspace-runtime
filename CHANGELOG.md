# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2025-10-31]

### Added
- Added Dependabot configuration for automated dependency updates

### Changed
- Split GitHub Actions workflow into separate pipelines for each component (base, vscode, jetbrains, cursor)
- Updated workflows to only trigger when corresponding component files are modified
- Improved documentation in README.md

### Removed
- Removed unified build-and-push.yml workflow file
- Removed test-images.sh script
