#!/usr/bin/env python3
"""require executed, passing tests rather than accepting an empty selector."""

import json
import re
import subprocess
import sys


def validate(summary, test_log=""):
    if (summary.get("result") != "Passed" or summary.get("passedTests", 0) < 1
            or summary.get("failedTests", 0)):
        raise ValueError("test evidence must contain passing tests with no failures")

    skipped = summary.get("skippedTests", 0)
    skip_reasons = re.findall(r"Test skipped - (.+)$", test_log, re.MULTILINE)
    if len(skip_reasons) != skipped or any(not reason.strip() for reason in skip_reasons):
        raise ValueError("every skipped test must have an explicit reason in the test log")


if __name__ == "__main__":
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--compact", "--path", sys.argv[1]
    ]))
    test_log = open(sys.argv[2], encoding="utf-8").read() if len(sys.argv) > 2 else ""
    validate(summary, test_log)
    print(f"verified {summary['passedTests']} passing tests, zero failures, "
          f"{summary.get('skippedTests', 0)} reasoned skips")
