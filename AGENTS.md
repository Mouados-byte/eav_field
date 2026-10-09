# Repository Guidelines

## Project Structure & Module Organization

The `eav_field` directory currently has no application source, tests, assets, or build configuration. Use these suggested locations when scaffolding the project, unless the selected framework requires another layout:

- `src/`: implementation code, grouped by feature or responsibility.
- `tests/`: automated tests organized to mirror source modules.
- `assets/`: static resources, if needed.
- `README.md`: project purpose, setup instructions, and supported workflows.

Keep generated output separate from maintained source and exclude it through `.gitignore`.

## Build, Test, and Development Commands

No installation, development, build, lint, or test commands are currently configured. Establish them with the chosen toolchain and document the exact commands in `README.md`. Include required runtime versions and configuration steps. Verify commands from the repository root before documenting them; do not assume commands such as `npm test` exist.

## Coding Style & Naming Conventions

No language-specific style or formatter is configured. When introducing a language, adopt its standard formatter and linter, commit their configuration, and follow their indentation defaults. Use descriptive names and consistent filename conventions. Keep modules focused and avoid unrelated formatting changes. For Markdown, use descriptive headings and fenced code blocks with language labels.

## Testing Guidelines

No test framework or coverage threshold exists yet. Add an appropriate framework alongside the first implementation. Use its discovery conventions, such as `test_<module>.py` for pytest or `<module>.test.ts` for a compatible TypeScript runner. Cover new behavior, boundary cases, and regression fixes; document how contributors run the suite.

## Commit & Pull Request Guidelines

This directory has no Git history, so no established commit convention can be inferred. Use concise, imperative subjects, for example `Add initial project scaffold`. Keep commits focused. Pull requests should explain the change, link relevant issues, and list validation commands and results. Include screenshots when changing a user interface, and call out setup changes.

## Configuration

Keep credentials out of tracked files. When configuration is introduced, provide a placeholder-only `.env.example` and document required variables in `README.md`.
