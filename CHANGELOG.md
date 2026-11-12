# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]
* A pinned heading starts with the page's status: a run's, a defect's state and severity, a target's latest run's
* A pinned heading keeps to the page's width (`mayhem-max-width`)
* vui pins the heading in the header line now: update vui to its 2026-11-10 snapshot or later
* A sync store made by a newer mayhem.el is recreated, not refused
* A page scrolled past its heading keeps it in the header line; a click on it goes to the top (`mayhem-sticky-title`)
* `C-c C-o` and `mayhem-copy-url` take the row or link at point, else the page
* `mayhem-copy-url` copies the page's web app link; with `C-u`, its short reference, as `o/p/t/7`
