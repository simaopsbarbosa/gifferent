#!/usr/bin/env python3
"""require executed, passing tests rather than accepting an empty selector."""

import json
import subprocess
import sys


def validate(summary):
    if (summary.get("result") != "Passed" or summary.get("passedTests", 0) < 1
            or summary.get("failedTests", 0) or summary.get("skippedTests", 0)):
        raise ValueError("test evidence must contain passing tests with no failures or skips")


if __name__ == "__main__":
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--compact", "--path", sys.argv[1]
    ]))
    validate(summary)
    print(f"verified {summary['passedTests']} passing tests, zero failures and skips")
