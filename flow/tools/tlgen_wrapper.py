# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

import hjson
from . import tlgen
from pydesignflow import Block, action, Result
from pathlib import Path

def run_tlgen(input_fn: Path, output_rtl_sv: Path, output_pkg_sv: Path):
    """
    Args:
        input_fn: Input HJSON filename
        output_dir: Output directory
        result: pydesignflow Result object that will be modified
    """    

    with open(input_fn) as f_in:
        obj = hjson.load(f_in, use_decimal=True)

    xbar = tlgen.validate(obj)
    if not tlgen.elaborate(xbar):
        raise Exception(f"Elaboration failed: {xbar}")

    results = tlgen.generate(xbar)

    for filename, filecontent in results:
        #filepath = output_dir / filename
        #filepath.parent.mkdir(parents=True, exist_ok=True)

        if filename.endswith('_pkg.sv'):
            pkg_sv_code = filecontent
        elif filename.endswith('.sv'):
            rtl_sv_code = filecontent

    with open(output_rtl_sv, "w") as f:
        f.write(rtl_sv_code)

    with open(output_pkg_sv, "w") as f:
        f.write(pkg_sv_code)
