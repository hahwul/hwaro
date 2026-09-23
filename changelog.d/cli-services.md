### Fixed
- CLI writers now refuse symlinks that escape their project roots. Import, export, and deploy skip sources linked outside their input trees; conversion preserves in-project symlink behavior and skips targets outside the project.
