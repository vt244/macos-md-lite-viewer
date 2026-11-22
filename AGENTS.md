# Repository Guidelines

## Project Structure

The application entry point is `Sources/main.swift`. App and shared preview code live in `Sources/`, the Finder Quick Look extension in `Extensions/QuickLook/`, bundled assets in `Resources/`, and tests in `Tests/`. Keep test Markdown fixtures with the tests that use them. Keep generated build output and temporary files out of version control.

## Build, Test, and Development

Use macOS 13 or newer with Xcode Command Line Tools that include Swift and the macOS 13 SDK or newer. This repository builds directly with `swiftc`. Run `./Scripts/build.sh` to build and sign the app, `open ".build/Markdown Viewer.app"` to launch it, and `./Scripts/test.sh` to run the tests and validate the property lists. See `README.md` for the manual viewer and Quick Look checks. Run the documented checks before submitting a change and report the checks you ran.

## Coding Style and Testing

Follow the conventions established by the first source files. When introducing a formatter or linter, commit its configuration and document how contributors can run it. Use descriptive names that identify the behavior under test, such as `opensLocalMarkdownFile`. For changes to Markdown rendering or file opening, cover the affected behavior with a small fixture or focused test. Include manual verification steps for UI behavior when automated coverage is unavailable.

## Commits and Pull Requests

Use a short imperative commit subject, such as `Handle empty Markdown files`. In pull requests, describe the user-visible change, link the related issue when one exists, and record verification steps. Include screenshots for changes to the viewer’s layout or rendering.

## Working Files

Create all files inside the project by default, including scripts, logs, backups, reports, and intermediate artifacts, on local and remote machines. Use a project-local directory such as `.tmp/` for temporary work and remove it when finished. Write outside the project only to a path the user explicitly requests.
