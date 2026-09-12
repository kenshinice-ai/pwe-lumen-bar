#!/bin/bash
# The one place the version number lives. Everything that needs it — the bundle,
# the disk image, the site's download link — reads it from here, so a release can
# never ship two different numbers.
echo "1.1.1"
