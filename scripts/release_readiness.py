#!/usr/bin/env python3
import sys

sys.dont_write_bytecode = True

from content_checks import (
    check_legacy_identifiers,
    check_unreviewed,
    release_safety,
    report,
    validate_content,
    verify_app_icon,
    verify_privacy,
    verify_storekit,
)
from content_review_checks import production_boundary_errors


errors = (
    validate_content()
    + check_unreviewed()
    + verify_storekit()
    + verify_privacy()
    + verify_app_icon()
    + check_legacy_identifiers()
    + release_safety()
    + production_boundary_errors()
)
raise SystemExit(report("Release readiness", errors))
