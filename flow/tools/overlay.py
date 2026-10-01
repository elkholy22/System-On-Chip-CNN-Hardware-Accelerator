# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

from pathlib import Path
import os

def use_solutions_overlay():
    try:
        return os.environ["SOLUTIONS"] == "1"
    except KeyError:
        return False

def filter_solutions_overlay(filenames: list[Path], src_dir: Path):
    if not use_solutions_overlay():
        return filenames
    res = []
    solutions_dir = src_dir.parent / "rvlab-solutions"
    for fn in filenames:
        if fn.is_relative_to(src_dir):
            fn_overlay = solutions_dir / fn.relative_to(src_dir)
            if fn_overlay.exists():
                print(f"Info: Using solutions overlay file {fn_overlay}")
                fn = fn_overlay

        assert isinstance(fn, Path)
        res.append(fn)

    return res
